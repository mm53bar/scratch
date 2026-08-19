# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_19_120000) do
  create_table "artists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "sort_name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_artists_on_name", unique: true
    t.index ["sort_name"], name: "index_artists_on_sort_name"
  end

  create_table "release_groups", force: :cascade do |t|
    t.integer "artist_id", null: false
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["artist_id", "title"], name: "index_release_groups_on_artist_id_and_title", unique: true
    t.index ["artist_id"], name: "index_release_groups_on_artist_id"
  end

  create_table "releases", force: :cascade do |t|
    t.date "acquired_on"
    t.datetime "created_at", null: false
    t.string "edition"
    t.string "medium", null: false
    t.text "notes"
    t.string "path"
    t.integer "release_group_id", null: false
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["medium"], name: "index_releases_on_medium"
    t.index ["path"], name: "index_releases_on_path", unique: true
    t.index ["release_group_id", "medium"], name: "index_releases_on_release_group_id_and_medium"
    t.index ["release_group_id"], name: "index_releases_on_release_group_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.string "artist_credit"
    t.bigint "byte_size"
    t.datetime "created_at", null: false
    t.integer "disc", default: 1, null: false
    t.integer "duration_seconds"
    t.string "file_format"
    t.string "filename"
    t.integer "position", null: false
    t.integer "release_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["release_id", "disc", "position"], name: "index_tracks_on_release_id_and_disc_and_position", unique: true
    t.index ["release_id"], name: "index_tracks_on_release_id"
  end

  add_foreign_key "release_groups", "artists"
  add_foreign_key "releases", "release_groups"
  add_foreign_key "tracks", "releases"
end
