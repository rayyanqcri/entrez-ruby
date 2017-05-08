module RayyanScrapers
  class PubMedHealthFulltextScraper < PubMedHealthScraper
    def initialize
      super
      @search_url = "#{@base_url}/s/full_text_reviews_medrev"
      @logger.debug "PubMedHealthFulltext scraper initialized"
    end
  end
end
