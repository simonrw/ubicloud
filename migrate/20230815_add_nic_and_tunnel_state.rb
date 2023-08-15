# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:nic) do
      add_column :state, :text, null: false, default: "creating"
    end
    alter_table(:ipsec_tunnel) do
      add_column :state, :text, null: false, default: "waiting"
    end
  end
end
