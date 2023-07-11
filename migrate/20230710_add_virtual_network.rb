Sequel.migration do
  change do
    create_table(:virtual_network) do
      add_column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      add_column :ip4_range, :inet, null: false
      add_column :ip6_range, :inet, null: false
      add_column :location, :text, null: false
      add_column :name, :text, null: false
    end

    alter_table(:vm) do
      add_foreign_key :virtual_network_id, :virtual_network, type: :uuid
    end
  end
end