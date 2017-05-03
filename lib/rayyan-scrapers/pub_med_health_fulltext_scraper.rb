module RayyanScrapers
  class PubMedHealthFulltextScraper < PubMedHealthScraper
    def initialize(query)
      super(query)
      @search_url = "#{@base_url}/s/full_text_reviews_medrev"
      @logger.debug "PubMedHealthFulltext scraper initialized with query #{@query}"
    end
  end
end
