namespace :library do
  desc "Scan the music library and update the catalogue"
  task scan: :environment do
    root = Scratch.library_root
    abort "library not readable: #{root}" unless root.directory?

    ScanRun.release_stale
    abort "a scan is already running" if ScanRun.current

    # Recorded the same way a scan started from the web is, so the history on
    # the Library page is the whole history rather than part of it.
    run = ScanRun.create!(started_at: Time.current, triggered_by: "cli")
    puts "scanning #{root}"

    begin
      result = LibraryScan.new.call do |done, total|
        run.update_columns(albums_done: done, albums_total: total, updated_at: Time.current)
      end
      run.update!(status: "completed", finished_at: Time.current,
                  albums: result.albums, tracks: result.tracks,
                  created: result.created, updated: result.updated, skipped: result.skipped)
    rescue StandardError => e
      run.update_columns(status: "failed", finished_at: Time.current, updated_at: Time.current,
                         error: "#{e.class}: #{e.message}")
      raise
    end

    puts "  #{run.summary}"
    puts "  took #{run.duration}s"

    if run.skipped.any?
      puts "  skipped (no readable tags):"
      run.skipped.first(20).each { |d| puts "    #{d}" }
      puts "    … and #{run.skipped.size - 20} more" if run.skipped.size > 20
    end
  end
end
