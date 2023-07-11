# frozen_string_literal: true

require "netaddr"
require "ulid"
require "base64"
require "securerandom"

class Prog::VnetNexus < Prog::Base
  semaphore :destroy, :refresh_mesh

  def self.assemble(name, location, ip4_range: nil, ip6_range: nil, ip4_len: 28, ip6_len: 64)
    id = SecureRandom.uuid
    base_ip4_range = NetAddr.parse_net("192.168.0.0/16")
    base_ip6_range = NetAddr.parse_net("fd00::/8")

    ip4_range ||= NetAddr::IPv4Net.new(base_ip4_range.nth(SecureRandom.random_number(2**(32 - ip4_len)).to_i), NetAddr::Mask32.new(ip4_len))
    ip6_range ||= NetAddr::IPv6Net.new(base_ip6_range.nth(SecureRandom.random_number(2**(128 - ip6_len)).to_i), NetAddr::Mask128.new(ip6_len))

    ip4_range = NetAddr::IPv4Net.new(ip4_range.network, NetAddr::Mask32.new(ip4_len))
    ip6_range = NetAddr::IPv6Net.new(ip6_range.network, NetAddr::Mask128.new(ip6_len))

    VirtualNetwork.create(ip4_range: ip4_range, ip6_range: ip6_range, name: name, location: location)  { _1.id = id }
    Strand.create(prog: "VnetNexus", label: "wait") { _1.id = id }
  end

  def wait
    if when_destroy_set?
      destroy
    end

    if when_refresh_mesh_set?
      refresh_mesh
    end
  end

  def resources
    virtual_network.Vms
  end

  def refresh_mesh 
    resources.each do |rec|
      unless Config.development?
        decr_refresh_mesh
        hop :wait
      end
      
      # TODO: create ipsec tunnels in between each resource
      # Create private routes to each resource per resource

      decr_refresh_mesh

      hop :wait
    end
  end
end