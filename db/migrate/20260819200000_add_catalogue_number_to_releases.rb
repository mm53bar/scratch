class AddCatalogueNumberToReleases < ActiveRecord::Migration[8.1]
  def change
    # The number printed on the label and the spine. For anything pressed
    # before barcodes it is the only identifier a record carries, and it stays
    # useful afterwards because it names the edition rather than the shipment.
    add_column :releases, :catalogue_number, :string
    add_index :releases, :catalogue_number

    # Two pressings can share a catalogue number across territories, so the
    # number alone does not say which one is on the shelf.
    add_column :releases, :country, :string, limit: 2

    # Provenance for anything filled in from a lookup, and the key for asking
    # again later. Unique because two shelf entries pointing at one pressing is
    # a duplicate, not a collection of two.
    add_column :releases, :musicbrainz_release_id, :string
    add_index :releases, :musicbrainz_release_id, unique: true
  end
end
