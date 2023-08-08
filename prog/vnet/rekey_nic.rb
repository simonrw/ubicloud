# frozen_string_literal: true

class Prog::Vnet::RekeyNic < Prog::Base
  subject_is :nic
  semaphore :trigger_policy

  def all_tunnels
    nic.src_ipsec_tunnels + nic.dst_ipsec_tunnels
  end

  def start
    args = frame["payload"][nic.id]

    all_tunnels.each do |tunnel|
      args = frame["payload"][tunnel.src_nic.id]
      create_state(tunnel, args)
    end

    hop :wait_policy_trigger
  end

  def sshable_cmd(cmd)
    nic.vm.vm_host.sshable.cmd(cmd)
  end

  def create_state(tunnel, args)
    namespace = tunnel.vm_name(nic)
    src = subdivide_network(tunnel.src_nic.vm.ephemeral_net6).network
    dst = subdivide_network(tunnel.dst_nic.vm.ephemeral_net6).network
    reqid = args["reqid"]
    key = args["encryption_key"]
    sshable_cmd("sudo ip -n #{namespace} xfrm state add " \
      "src #{src} dst #{dst} proto esp spi #{args["spi4"]} reqid #{reqid} mode tunnel " \
      "aead 'rfc4106(gcm(aes))' #{key} 128 sel src 0.0.0.0/0 dst 0.0.0.0/0 ")
    sshable_cmd("sudo ip -n #{namespace} xfrm state add " \
      "src #{src} dst #{dst} proto esp spi #{args["spi6"]} reqid #{reqid} mode tunnel " \
      "aead 'rfc4106(gcm(aes))' #{key} 128")
  end

  def subdivide_network(net)
    prefix = net.netmask.prefix_len + 1
    halved = net.resize(prefix)
    halved.next_sib
  end

  def wait_policy_trigger
    if SemSnap.new(nic.id).set?("trigger_policy")
      SemSnap.new(nic.id).decr("trigger_policy")
      hop :replace_policies
    end
    nap 1
  end

  def upsert_policy(namespace, src, dst, tmpl_src, tmpl_dst, reqid, spi, dir)
    policy_not_exists = sshable_cmd("sudo ip -n #{namespace} xfrm policy show " \
      "src #{src} dst #{dst} dir #{dir} tmpl src #{tmpl_src} dst #{tmpl_dst} ").empty?
    
    put_type = policy_not_exists ? "add" : "update"
    sshable_cmd("sudo ip -n #{namespace} xfrm policy #{put_type} " \
      "src #{src} dst #{dst} dir #{dir} tmpl src #{tmpl_src} dst #{tmpl_dst} " \
      "spi #{spi} proto esp reqid #{reqid} mode tunnel")
  end


  def policy_update(tunnel, dir)
    namespace = tunnel.vm_name(nic)
    tmpl_src = subdivide_network(tunnel.src_nic.vm.ephemeral_net6).network
    tmpl_dst = subdivide_network(tunnel.dst_nic.vm.ephemeral_net6).network
    reqid = frame["payload"][tunnel.src_nic.id]["reqid"]
    src4 = tunnel.src_nic.private_ipv4
    dst4 = tunnel.dst_nic.private_ipv4
    src6 = tunnel.src_nic.private_ipv6
    dst6 = tunnel.dst_nic.private_ipv6
    spi4 = frame["payload"][tunnel.src_nic.id]["spi4"]
    spi6 = frame["payload"][tunnel.src_nic.id]["spi6"]

    upsert_policy(namespace, src4, dst4, tmpl_src, tmpl_dst, reqid, spi4, dir)
    upsert_policy(namespace, src6, dst6, tmpl_src, tmpl_dst, reqid, spi6, dir)
  end

  def replace_policies
    nic.src_ipsec_tunnels.each { |tunnel| policy_update(tunnel, "out") }
    nic.dst_ipsec_tunnels.each { |tunnel| policy_update(tunnel, "fwd") }

    hop :wait_state_drop_trigger
  end

  def wait_state_drop_trigger
    if SemSnap.new(nic.id).set?("old_state_drop")
      # fix sem decr, not working
      SemSnap.new(nic.id).decr("old_state_drop")
      hop :old_state_drop
    end

    nap 1
  end

  def old_state_drop
    sshable = nic.vm.vm_host.sshable
    policy_data = sshable.cmd("sudo ip -n #{nic.src_ipsec_tunnels.first.vm_name(nic)} xfrm policy")
    state_data = sshable.cmd("sudo ip -n #{nic.src_ipsec_tunnels.first.vm_name(nic)} xfrm state")

    # Extract SPIs from policy data
    policy_spis = policy_data.scan(/spi (0x[0-9a-f]+)/).flatten

    # Extract SPIs along with src and dst from state data
    states = state_data.scan(/^src (\S+) dst (\S+).*?proto esp spi (0x[0-9a-f]+)/m)

    # Identify which states to drop
    states_to_drop = states.reject { |(_, _, spi)| policy_spis.include?(spi) }

    states_to_drop.each do |src, dst, spi|
      sshable.cmd("sudo ip -n #{nic.src_ipsec_tunnels.first.vm_name(nic)} xfrm state delete src #{src} dst #{dst} proto esp spi #{spi}")
    end

    pop "wait_state_drop"
  end
end
