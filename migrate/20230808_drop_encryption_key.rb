# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:nic) do
      drop_column(:encryption_key)
    end
  end
end
