# frozen_string_literal: true

class Prog::Vnet::RekeyNicTunnel < Prog::Base
  subject_is :nic

  def all_tunnels
    nic.src_ipsec_tunnels + nic.dst_ipsec_tunnels
  end

  def setup_nic_tunnels
    nic.all_tunnels.each do |tunnel|
      args = tunnel.src_nic.rekey_payload
      create_state(tunnel, args)
      policy_upsert(tunnel, "out", "add")
      policy_upsert(tunnel, "fwd", "add")
      create_private_routes(tunnel)
    end

    pop "setup_nic_tunnels is complete"
  end

  def create_private_routes(tunnel)
    [tunnel.dst_nic.private_ipv6, tunnel.dst_nic.private_ipv4].each do |dst_ip|
      sshable_cmd("sudo ip -n #{tunnel.vm_name(nic)} route replace #{dst_ip.to_s.shellescape} dev vethi#{tunnel.vm_name(nic)}")
    end
  end

  def setup_inbound
    nic.dst_ipsec_tunnels.each do |tunnel|
      args = tunnel.src_nic.rekey_payload
      create_state(tunnel, args)
    end

    pop "inbound_setup is complete"
  end

  def setup_outbound
    nic.src_ipsec_tunnels.each do |tunnel|
      args = tunnel.src_nic.rekey_payload
      create_state(tunnel, args)
      policy_upsert(tunnel, "out", "update")
    end

    pop "outbound_setup is complete"
  end

  def drop_old_state
    new_spis = [nic.rekey_payload["spi4"], nic.rekey_payload["spi6"]]
    new_spis += nic.dst_ipsec_tunnels.map do |tunnel|
      [tunnel.src_nic.rekey_payload["spi4"], tunnel.src_nic.rekey_payload["spi6"]]
    end.flatten

    state_data = sshable_cmd("sudo ip -n #{nic.src_ipsec_tunnels.first.vm_name(nic)} xfrm state")

    # Extract SPIs along with src and dst from state data
    states = state_data.scan(/^src (\S+) dst (\S+).*?proto esp spi (0x[0-9a-f]+)/m)

    # Identify which states to drop
    states_to_drop = states.reject { |(_, _, spi)| new_spis.include?(spi) }
    states_to_drop.each do |src, dst, spi|
      sshable_cmd("sudo ip -n #{nic.src_ipsec_tunnels.first.vm_name(nic)} xfrm state delete src #{src} dst #{dst} proto esp spi #{spi}")
    end

    pop "drop_old_state is complete"
  end

  def sshable_cmd(cmd)
    nic.vm.vm_host.sshable.cmd(cmd)
  end

  def create_state(tunnel, args)
    namespace = tunnel.vm_name(nic)
    src = subdivide_network(tunnel.src_nic.vm.ephemeral_net6).network
    dst = subdivide_network(tunnel.dst_nic.vm.ephemeral_net6).network
    reqid = args["reqid"]
    key = tunnel.src_nic.encryption_key

    sshable_cmd("sudo ip -n #{namespace} xfrm state add " \
      "src #{src} dst #{dst} proto esp spi #{args["spi4"]} reqid #{reqid} mode tunnel " \
      "aead 'rfc4106(gcm(aes))' #{key} 128 sel src 0.0.0.0/0 dst 0.0.0.0/0 ")
    sshable_cmd("sudo ip -n #{namespace} xfrm state add " \
      "src #{src} dst #{dst} proto esp spi #{args["spi6"]} reqid #{reqid} mode tunnel " \
      "aead 'rfc4106(gcm(aes))' #{key} 128")
  end

  def policy_cmd(namespace, src, dst, tmpl_src, tmpl_dst, reqid, spi, dir, cmd)
    sshable_cmd("sudo ip -n #{namespace} xfrm policy #{cmd} " \
      "src #{src} dst #{dst} dir #{dir} tmpl src #{tmpl_src} dst #{tmpl_dst} " \
      "proto esp reqid #{reqid} mode tunnel")
  end

  def policy_upsert(tunnel, dir, cmd)
    namespace = tunnel.vm_name(nic)
    tmpl_src = subdivide_network(tunnel.src_nic.vm.ephemeral_net6).network
    tmpl_dst = subdivide_network(tunnel.dst_nic.vm.ephemeral_net6).network
    reqid = tunnel.src_nic.rekey_payload["reqid"]
    src4 = tunnel.src_nic.private_ipv4
    dst4 = tunnel.dst_nic.private_ipv4
    src6 = tunnel.src_nic.private_ipv6
    dst6 = tunnel.dst_nic.private_ipv6
    spi4 = tunnel.src_nic.rekey_payload["spi4"]
    spi6 = tunnel.src_nic.rekey_payload["spi6"]

    policy_update_cmd(namespace, src4, dst4, tmpl_src, tmpl_dst, reqid, spi4, dir, cmd)
    policy_update_cmd(namespace, src6, dst6, tmpl_src, tmpl_dst, reqid, spi6, dir, cmd)
  end

  def subdivide_network(net)
    prefix = net.netmask.prefix_len + 1
    halved = net.resize(prefix)
    halved.next_sib
  end
end
