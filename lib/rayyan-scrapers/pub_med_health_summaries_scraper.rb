module RayyanScrapers
  class PubMedHealthSummariesScraper < PubMedHealthScraper
    def initialize(query, content_dir = 'pubmedhealthsummaries-contents')
      super(query, content_dir)
      @search_url = "#{@base_url}/s/executive_summaries_medrev"
      @logger.debug "PubMedHealthSummaries scraper initialized with query #{@query}"
      @source = Source.find_by_name 'PubMed Health Executive Summaries'
    end
  end
end
