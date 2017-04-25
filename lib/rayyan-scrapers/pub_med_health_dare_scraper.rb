module RayyanScrapers
  class PubMedHealthDareScraper < PubMedHealthScraper
    def initialize(query, content_dir = 'pubmedhealthdare-contents')
      super(query, content_dir)
      @search_url = "#{@base_url}/s/dare_reviews_medrev"
      @logger.debug "PubMedHealthDARE scraper initialized with query #{@query}"
      @source = Source.find_by_name 'PubMed Health DARE'
    end
  end
end
