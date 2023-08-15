# frozen_string_literal: true

class Prog::Vnet::NicNexus < Prog::Base
  subject_is :nic
  semaphore :destroy, :detach_vm, :start_rekey, :trigger_outbound_update, :old_state_drop_trigger, :setup_nic, :setup_trigger, :setup_dst_nic_tunnels, :all_finish

  def self.assemble(private_subnet_id, name: nil, ipv6_addr: nil, ipv4_addr: nil)
    unless (subnet = PrivateSubnet[private_subnet_id])
      fail "Given subnet doesn't exist with the id #{private_subnet_id}"
    end

    ubid = Nic.generate_ubid
    name ||= Nic.ubid_to_name(ubid)

    ipv6_addr ||= subnet.random_private_ipv6.to_s
    ipv4_addr ||= subnet.random_private_ipv4.to_s

    DB.transaction do
      Nic.create(private_ipv6: ipv6_addr, private_ipv4: ipv4_addr, mac: gen_mac,
        name: name, private_subnet_id: private_subnet_id) { _1.id = ubid.to_uuid }
      Strand.create(prog: "Vnet::NicNexus", label: "wait_vm") { _1.id = ubid.to_uuid }
    end
  end

  def before_run
    when_destroy_set? do
      hop :destroy if strand.label != "destroy"
    end
  end

  def wait_vm
    when_setup_nic_set? do
      hop :setup_nic
    end
    nap 5
  end

  def setup_nic
    nic.private_subnet.add_nic(nic)
    hop :wait_setup_trigger
  end

  def wait_setup_trigger
    when_setup_trigger_set? do
      if nic.src_ipsec_tunnels.empty?
        nic.update(state: "waiting")
        decr_setup_trigger
        hop :wait
      end
      hop :setup_tunnel
    end
    donate
  end

  def setup_tunnel
    bud Prog::Vnet::RekeyNicTunnel, {}, :setup_nic_tunnels
    hop :wait_setup_tunnels
  end

  def wait_setup_tunnels
    reap
    if leaf?
      # nic.src_ipsec_tunnels.each { _1.update(state: "created") }
      nic.update(state: "created")
      decr_setup_trigger
      hop :wait_until_all_finish
    end
    donate
  end

  def wait
    when_detach_vm_set? do
      hop :detach_vm
    end

    when_start_rekey_set? do
      hop :start_rekey
    end

    when_setup_dst_nic_tunnels_set? do
      bud Prog::Vnet::RekeyNicTunnel, {}, :setup_nic_tunnels
      hop :wait_setup_dst_nic_tunnels
    end

    nap 30
  end

  def wait_setup_dst_nic_tunnels
    reap
    if leaf?
      decr_setup_dst_nic_tunnels
      hop :wait_until_all_finish
    end
    donate
  end

  def wait_until_all_finish
    when_all_finish_set? do
      decr_all_finish
      hop :wait
    end
    donate
  end

  def start_rekey
    bud Prog::Vnet::RekeyNicTunnel, {}, :setup_inbound
    hop :wait_rekey_inbound
  end

  def wait_rekey_inbound
    reap
    if leaf?
      decr_start_rekey
      hop :wait_rekey_outbound_trigger
    end
    donate
  end

  def wait_rekey_outbound_trigger
    when_trigger_outbound_update_set? do
      bud Prog::Vnet::RekeyNicTunnel, {}, :setup_outbound
      hop :wait_rekey_outbound
    end
    donate
  end

  def wait_rekey_outbound
    reap
    if leaf?
      decr_trigger_outbound_update
      hop :wait_rekey_old_state_drop_trigger
    end
    donate
  end

  def wait_rekey_old_state_drop_trigger
    when_old_state_drop_trigger_set? do
      bud Prog::Vnet::RekeyNicTunnel, {}, :drop_old_state
      hop :wait_rekey_old_state_drop
    end
    donate
  end

  def wait_rekey_old_state_drop
    reap
    if leaf?
      decr_old_state_drop_trigger
      hop :wait
    end
    donate
  end

  def destroy
    if nic.vm
      fail "Cannot destroy nic with active vm, first clean up the attached resources"
    end

    DB.transaction do
      nic.src_ipsec_tunnels_dataset.destroy
      nic.dst_ipsec_tunnels_dataset.destroy
      nic.destroy
    end

    pop "nic deleted"
  end

  def detach_vm
    DB.transaction do
      nic.update(vm_id: nil)
      nic.src_ipsec_tunnels_dataset.destroy
      nic.dst_ipsec_tunnels_dataset.destroy
      decr_detach_vm
    end

    hop :wait
  end

  # Generate a MAC with the "local" (generated, non-manufacturer) bit
  # set and the multicast bit cleared in the first octet.
  #
  # Accuracy here is not a formality: otherwise assigning a ipv6 link
  # local address errors out.
  def self.gen_mac
    ([rand(256) & 0xFE | 0x02] + Array.new(5) { rand(256) }).map {
      "%0.2X" % _1
    }.join(":").downcase
  end
end
