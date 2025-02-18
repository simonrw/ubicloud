#!/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/common"
require_relative "../lib/cloud_hypervisor"
require "fileutils"

# YYY: we should check against digests of each artifact, to detect and
# report any unexpected content changes (e.g., supply chain attack).

ch_dir = "/opt/cloud-hypervisor/v#{CloudHypervisor::VERSION}"
FileUtils.mkdir_p(ch_dir)
FileUtils.cd ch_dir do
  r "curl -L3 -O https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/v#{CloudHypervisor::VERSION}/ch-remote"
  FileUtils.chmod "a+x", "ch-remote"
  r "curl -L3 -O https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/v#{CloudHypervisor::VERSION}/cloud-hypervisor"
  FileUtils.chmod "a+x", "cloud-hypervisor"
end

# edk2 firmware
fw_dir = File.dirname(CloudHypervisor.firmware)
FileUtils.mkdir_p(fw_dir)
FileUtils.cd fw_dir do
  r "curl -L3 -o #{CloudHypervisor.firmware.shellescape} https://github.com/fdr/edk2/releases/download/#{CloudHypervisor::FIRMWARE_VERSION}/CLOUDHV.fd"
end

# Host-level network packet forwarding, otherwise packets cannot leave
# the physical interface.
File.write("/etc/sysctl.d/72-clover-forward-packets.conf", <<CONF)
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
net.ipv4.conf.all.forwarding=1
net.ipv4.ip_forward=1
CONF
r "sysctl --system"

# OS images.

# For qemu-image convert and mcopy for cloud-init with the nocloud
# driver.
r "apt-get -y install qemu-utils mtools"
