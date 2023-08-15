# frozen_string_literal: true

class Prog::Vnet::SubnetNexus < Prog::Base
  semaphore :destroy, :refresh_keys, :add_new_nic

  def self.assemble(project_id, name: nil, location: "hetzner-hel1", ipv6_range: nil, ipv4_range: nil)
    project = Project[project_id]
    unless project || Config.development?
      fail "No existing project"
    end

    ubid = PrivateSubnet.generate_ubid
    name ||= PrivateSubnet.ubid_to_name(ubid)

    Validation.validate_name(name)
    Validation.validate_location(location, project&.provider)

    ipv6_range ||= random_private_ipv6(location).to_s
    ipv4_range ||= random_private_ipv4(location).to_s
    DB.transaction do
      ps = PrivateSubnet.create(name: name, location: location, net6: ipv6_range, net4: ipv4_range, state: "waiting") { _1.id = ubid.to_uuid }
      ps.associate_with_project(project)
      Strand.create(prog: "Vnet::SubnetNexus", label: "wait") { _1.id = ubid.to_uuid }
    end
  end

  def ps
    @ps ||= PrivateSubnet[strand.id]
  end

  def rekeying_nics
    ps.nics.select { !_1.rekey_payload.nil? }
  end

  def wait
    when_destroy_set? do
      hop :destroy
    end

    when_refresh_keys_set? do
      ps.update(state: "refreshing_keys")
      hop :refresh_keys
    end

    when_add_new_nic_set? do
      ps.update(state: "adding_new_nic")
      hop :add_new_nic
    end

    nap 30
  end

  def gen_encryption_key
    "0x" + SecureRandom.bytes(36).unpack1("H*")
  end

  def gen_spi
    "0x" + SecureRandom.bytes(4).unpack1("H*")
  end

  def gen_reqid
    SecureRandom.random_number(100000) + 1
  end

  def add_new_nic
    nic = ps.to_be_added_nics.first
    unless nic
      ps.update(state: "waiting")
      decr_add_new_nic
      hop :wait
    end

    if ps.active_nics.count == 0
      nic.incr_setup_trigger
      hop :wait
    end

    ps.active_nics.each do |active_nic|
      payload = {
        spi4: gen_spi,
        spi6: gen_spi,
        reqid: gen_reqid
      }
      active_nic.update(encryption_key: gen_encryption_key, rekey_payload: payload)
    end
    nic.update(encryption_key: gen_encryption_key, rekey_payload: {spi4: gen_spi, spi6: gen_spi, reqid: gen_reqid})

    ps.active_nics.each do |active_nic|
      active_nic.incr_setup_dst_nic_tunnels
    end

    nic.incr_setup_trigger
    hop :wait_setup
  end

  def wait_setup
    puts "rekeying_nics: #{rekeying_nics.count}"
    puts "LABELS: #{rekeying_nics.map(&:strand).map(&:label)}"
    if rekeying_nics.all? { |nic| nic.strand.label == "wait_until_all_finish" }
      if ps.to_be_added_nics.count == 0
        decr_add_new_nic
        incr_refresh_keys
      end
      rekeying_nics.each(&:incr_all_finish)
      hop :wait
    end
    donate
  end

  def refresh_keys
    ps.nics.each do |nic|
      payload = {
        spi4: gen_spi,
        spi6: gen_spi,
        reqid: gen_reqid
      }
      nic.update(encryption_key: gen_encryption_key, rekey_payload: payload)
    end

    ps.nics.each do |nic|
      nic.incr_start_rekey
    end

    hop :wait_inbound_setup
  end

  def wait_inbound_setup
    if rekeying_nics.all? { |nic| nic.strand.label == "wait_rekey_outbound_trigger" }
      ps.nics.each(&:incr_trigger_outbound_update)
      hop :wait_outbound_setup
    end

    donate
  end

  def wait_outbound_setup
    if rekeying_nics.all? { |nic| nic.strand.label == "wait_rekey_old_state_drop_trigger" }
      ps.nics.each(&:incr_old_state_drop_trigger)
      hop :wait_old_state_drop
    end

    donate
  end

  def wait_old_state_drop
    if rekeying_nics.all? { |nic| nic.strand.label == "wait" }
      ps.update(state: "waiting")
      decr_refresh_keys unless ps.nics.any? { _1.rekey_payload.nil? }
      rekeying_nics.each do |nic|
        nic.update(encryption_key: nil, rekey_payload: nil)
      end

      hop :wait
    end
    donate
  end

  def destroy
    if ps.nics.any? { |n| !n.vm_id.nil? }
      fail "Cannot destroy subnet with active nics, first clean up the attached resources"
    end

    if ps.nics.empty?
      DB.transaction do
        ps.projects.each { |p| ps.dissociate_with_project(p) }
        ps.destroy
      end
      pop "subnet destroyed"
    else
      ps.nics.map { |n| n.incr_destroy }
      nap 1
    end
  end

  def self.random_private_ipv6(location)
    network_address = NetAddr::IPv6.new((SecureRandom.bytes(7) + 0xfd.chr).unpack1("Q<") << 64)
    network_mask = NetAddr::Mask128.new(64)
    addr = NetAddr::IPv6Net.new(network_address, network_mask)
    return random_private_ipv6(location) unless PrivateSubnet.where(net6: addr.to_s, location: location).first.nil?

    addr
  end

  def self.random_private_ipv4(location)
    private_range = PrivateSubnet.random_subnet
    addr = NetAddr::IPv4Net.parse(private_range)

    selected_addr = addr.nth_subnet(26, SecureRandom.random_number(2**(26 - addr.netmask.prefix_len) - 1).to_i + 1)
    return random_private_ipv4(location) unless PrivateSubnet.where(net4: selected_addr.to_s, location: location).first.nil?

    selected_addr
  end
end
