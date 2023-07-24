# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Vm do
  subject(:vm) { described_class.new }

  describe "#mem_gib" do
    it "handles the 'm5a' instance line" do
      vm.line = "m5a"
      vm.core_count = 1
      expect(vm.mem_gib).to eq 4
    end

    it "handles the 'c5a' instance line" do
      vm.line = "c5a"
      vm.core_count = 1
      expect(vm.mem_gib).to eq 2
    end

    it "crashes if a bogus line is passed" do
      vm.line = "nope"
      vm.core_count = 5
      expect { vm.mem_gib }.to raise_error RuntimeError, "BUG: unrecognized vm line"
    end
  end

  describe "#cloud_hypervisor_cpu_topology" do
    it "scales a single-socket hyperthreaded system" do
      vm.line = "m5a"
      vm.core_count = 2
      expect(vm).to receive(:vm_host).and_return(instance_double(
        VmHost,
        total_cpus: 12,
        total_cores: 6,
        total_nodes: 1,
        total_sockets: 1
      )).at_least(:once)
      expect(vm.cloud_hypervisor_cpu_topology.to_s).to eq("2:2:1:1")
    end

    it "scales a dual-socket hyperthreaded system" do
      vm.line = "m5a"
      vm.core_count = 2
      expect(vm).to receive(:vm_host).and_return(instance_double(
        VmHost,
        total_cpus: 24,
        total_cores: 12,
        total_nodes: 2,
        total_sockets: 2
      )).at_least(:once)
      expect(vm.cloud_hypervisor_cpu_topology.to_s).to eq("2:2:1:1")
    end

    it "crashes if total_cpus is not multiply of total_cores" do
      expect(vm).to receive(:vm_host).and_return(instance_double(
        VmHost,
        total_cpus: 3,
        total_cores: 2
      )).at_least(:once)

      expect { vm.cloud_hypervisor_cpu_topology }.to raise_error RuntimeError, "BUG"
    end

    it "crashes if total_nodes is not multiply of total_sockets" do
      expect(vm).to receive(:vm_host).and_return(instance_double(
        VmHost,
        total_cpus: 24,
        total_cores: 12,
        total_nodes: 3,
        total_sockets: 2
      )).at_least(:once)

      expect { vm.cloud_hypervisor_cpu_topology }.to raise_error RuntimeError, "BUG"
    end

    it "crashes if cores allocated per die is not uniform number" do
      vm.line = "m5a"
      vm.core_count = 2

      expect(vm).to receive(:vm_host).and_return(instance_double(
        VmHost,
        total_cpus: 1,
        total_cores: 1,
        total_nodes: 1,
        total_sockets: 1
      )).at_least(:once)

      expect { vm.cloud_hypervisor_cpu_topology }.to raise_error RuntimeError, "BUG: need uniform number of cores allocated per die"
    end

    context "with a dual socket Ampere Altra" do
      # YYY: Hacked up to pretend Ampere Altras have hyperthreading
      # for demonstration on small metal instances.

      before do
        expect(vm).to receive(:vm_host).and_return(instance_double(
          # Based on a dual-socket Ampere Altra running in quad-node
          # per chip mode.
          VmHost,
          total_cpus: 160,
          total_cores: 160,
          total_nodes: 8,
          total_sockets: 2
        )).at_least(:once)
      end

      it "prefers involving fewer sockets and numa nodes" do
        # Altra chips are 20 cores * 4 numa nodes, in the finest
        # grained configuration, such an allocation we prefer to grant
        # locality so the VM guest doesn't have to think about NUMA
        # until this size.
        vm.line = "m5a"
        vm.core_count = 20
        expect(vm.cloud_hypervisor_cpu_topology.to_s).to eq("1:20:1:1")
      end

      it "can compute bizarre, multi-node topologies for bizarre allocations" do
        vm.line = "m5a"
        vm.core_count = 90
        expect(vm.cloud_hypervisor_cpu_topology.to_s).to eq("1:15:3:2")
      end
    end
  end

  describe "#utility functions" do
    it "can compute the ipv4 addresses" do
      as_ad = instance_double(AssignedVmAddress, ip: NetAddr::IPv4Net.new(NetAddr.parse_ip("1.1.1.0"), NetAddr::Mask32.new(32)))
      expect(vm).to receive(:assigned_vm_address).and_return(as_ad).at_least(:once)
      expect(vm.ephemeral_net4.to_s).to eq("1.1.1.0")
      expect(vm.ip4.to_s).to eq("1.1.1.0/32")
    end

    it "can compute nil if ipv4 is not assigned" do
      expect(vm.ephemeral_net4).to be_nil
    end
  end
end
