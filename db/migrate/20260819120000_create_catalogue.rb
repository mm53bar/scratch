class CreateCatalogue < ActiveRecord::Migration[8.1]
  def change
    create_table :artists do |t|
      t.string :name, null: false
      # Sorting name — "Beatles, The" — so browsing is not led by articles.
      t.string :sort_name, null: false
      t.timestamps
    end
    add_index :artists, :name, unique: true
    add_index :artists, :sort_name

    # An album as a concept, independent of format. "Rumours" is one row no
    # matter how many pressings, editions or rips of it you own. This is the
    # join key that makes "on vinyl but not digitally" a group-by rather than a
    # matching problem.
    create_table :release_groups do |t|
      t.references :artist, null: false, foreign_key: true
      t.string :title, null: false
      # The album's own year, not a reissue's. Nullable because a shelf entry
      # may be added before anyone looks it up.
      t.integer :year
      t.timestamps
    end
    add_index :release_groups, %i[artist_id title], unique: true

    # A specific thing you own: this vinyl, that CD, the files on disk. Tracks
    # hang off releases rather than groups precisely so a deluxe CD with bonus
    # tracks and a nine-track vinyl of the same album can coexist.
    create_table :releases do |t|
      t.references :release_group, null: false, foreign_key: true
      t.string :medium, null: false
      # Edition title when it differs from the album — "Deluxe Edition",
      # "40th Anniversary". Nil means it is simply the album.
      t.string :edition
      # The year of THIS release, which for a reissue is not the album's year.
      t.integer :year
      t.date :acquired_on
      t.text :notes
      # Digital releases only: the folder, relative to the library root. Unique,
      # because it is how a rescan recognises a release it has already seen.
      t.string :path
      t.timestamps
    end
    add_index :releases, :medium
    add_index :releases, :path, unique: true
    add_index :releases, %i[release_group_id medium]

    create_table :tracks do |t|
      t.references :release, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :disc, null: false, default: 1
      t.string :title, null: false
      # The performer credited on this track, which on a compilation differs
      # from the release's artist. Nil means "same as the album artist".
      t.string :artist_credit
      t.integer :duration_seconds

      # File details, null for physical media — a vinyl track has no file. Kept
      # on the track rather than in a separate table because a track here has
      # exactly one file; see docs/adr.
      t.string :filename
      # Deliberately not called `format`: that shadows Kernel#format inside the
      # model and collides with `format` in controllers and views.
      t.string :file_format
      t.bigint :byte_size
      t.timestamps
    end
    add_index :tracks, %i[release_id disc position], unique: true
  end
end
