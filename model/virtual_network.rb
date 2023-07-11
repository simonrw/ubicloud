# frozen_string_literal: true

require_relative "../model"

class VirtualNetwork < Sequel::Model
  one_to_many :vms, key: :id, class: :Vm
  one_to_one :strand, key: :id
  # add other resources here
  
  def random_private_ipv6
    addr = NetAddr::IPv6Net.parse(ip6_range)
    network_mask = NetAddr::Mask128.new(64)
    ip6 = NetAddr::IPv6Net.new(addr.nth(SecureRandom.random_number(2**(128-addr.len))), network_mask)
    return random_private_ipv6 if is_ip6_used?(ip6)

    ip6
  end

  def random_private_ipv4
    addr = NetAddr::IPv4Net.parse(ip4_range)
    network_mask = NetAddr::Mask32.new(32)

    ip = NetAddr::IPv4Net.new(addr.nth(SecureRandom.random_number(2**(32 - addr.len))), network_mask)
    
    return random_private_ipv4 if is_ip4_used?(ip)
    
    ip
  end

  def is_ip4_used?(ip)
    # need to add other resources here
    vm.any? { |v| v.private_ipv4 == ip }
  end

  def is_ip6_used?(ip)
    # need to add other resources here
    # TODO: need to implement private_ipv6
    vm.any? { |v| v.private_ipv6 == ip }
  end
end
