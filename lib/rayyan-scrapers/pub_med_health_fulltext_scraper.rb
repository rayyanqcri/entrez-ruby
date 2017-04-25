module RayyanScrapers
  class PubMedHealthFulltextScraper < PubMedHealthScraper
    def initialize(query, content_dir = 'pubmedhealthfulltext-contents')
      super(query, content_dir)
      @search_url = "#{@base_url}/s/full_text_reviews_medrev"
      @logger.debug "PubMedHealthFulltext scraper initialized with query #{@query}"
      @source = Source.find_by_name 'PubMed Health Fulltext'
    end
  end
end
