module RayyanFormats
  module Plugins
    class PubmedXML < RayyanFormats::Base
      
      title 'PubMed XML'
      extension 'xml'
      description 'PubMed XML format'

      detect do |first_line, lines|
        first_line.start_with?('<?xml')
      end

      do_import do |body, filename, &block|
        total = RayyanScrapers::PubMedScraper.new(RayyanFormats::Base.logger).parse_search_results(body) do |target, total|
          block.call(target, total)
        end
        raise "Invalid XML, please follow the PubMed guide to export valid PubMed XML files" if total.nil? || total == 0
      end
      
    end # class
  end # module
end # module
