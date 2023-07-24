# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:vm) do
      add_column :core_count, Integer
      add_column :line, String, collate: '"C"'
    end

    run "UPDATE vm SET core_count = substring(size from 5 for 1)::int, line = substring(size from 1 for 3)"

    alter_table(:vm) do
      drop_column :size
      set_column_not_null :core_count
      set_column_not_null :line
    end
  end

  down do
    alter_table(:vm) do
      add_column :size, String, collate: '"C"'
    end

    run "UPDATE vm SET size = line || '.' || core_count::text || 'x'"

    alter_table(:vm) do
      drop_column :core_count
      drop_column :line
      set_column_not_null :size
    end
  end
end
