class CreateScanRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :scan_runs do |t|
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at

      # Known once the directories have been walked, which is why it is
      # nullable: for the first few seconds there is no denominator.
      t.integer :albums_total
      t.integer :albums_done, null: false, default: 0

      t.integer :albums, null: false, default: 0
      t.integer :tracks, null: false, default: 0
      t.integer :created, null: false, default: 0
      t.integer :updated, null: false, default: 0
      t.json :skipped, null: false, default: []

      t.text :error
      t.string :triggered_by, null: false, default: "web"

      t.timestamps
    end

    add_index :scan_runs, :started_at
    # Two scans at once would race on the same rows for no benefit, and the
    # second would be slower for it. Enforced by the database rather than by
    # a check-then-insert, which is a race of its own.
    add_index :scan_runs, :status, unique: true, where: "status = 'running'",
              name: "index_scan_runs_on_one_running"
  end
end
