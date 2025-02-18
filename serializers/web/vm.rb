# frozen_string_literal: true

class Serializers::Web::Vm < Serializers::Base
  def self.base(vm)
    {
      id: vm.id,
      ubid: vm.ubid,
      path: vm.path,
      name: vm.name,
      state: vm.display_state,
      location: vm.location,
      size: vm.size,
      storage_size_gib: vm.storage_size_gib,
      storage_encryption: vm.storage_encrypted? ? "encrypted" : "not encrypted",
      ip6: vm.ephemeral_net6&.nth(2),
      ip4: vm.ephemeral_net4
    }
  end

  structure(:default) do |vm|
    base(vm)
  end

  structure(:detailed) do |vm|
    base(vm).merge(
      {
        nics: vm.nics.map { |nic| Serializers::Web::Nic.serialize(nic) }
      }
    )
  end
end
