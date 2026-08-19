namespace :library do
  desc "Scan the music library and update the catalogue"
  task scan: :environment do
    root = Scratch.library_root
    abort "library not readable: #{root}" unless root.directory?

    puts "scanning #{root}"
    started = Time.current
    result = LibraryScan.new.call
    puts "  #{result}"
    puts "  took #{(Time.current - started).round(1)}s"

    if result.skipped.any?
      puts "  skipped (no readable tags):"
      result.skipped.first(20).each { |d| puts "    #{d}" }
      puts "    … and #{result.skipped.size - 20} more" if result.skipped.size > 20
    end
  end
end
