module RayyanScrapers
  class PubMedScraper < EntrezScraper
    def initialize(logger = nil, moneta_options = nil)
      super(logger, moneta_options)

      additional_params = "tool=#{self.class.client_tool_name}&email=#{self.class.client_tool_email}"
      @logger.debug "PubMedScraper configured with client tool information: #{additional_params}"

      @base_url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils'
      @search_url = "#{@base_url}/esearch.fcgi?db=pubmed&#{additional_params}"
      @detail_url = "#{@base_url}/efetch.fcgi?db=pubmed&retmode=xml&#{additional_params}"
      @detail_friendly_url = "https://www.ncbi.nlm.nih.gov/pubmed/"
      @refs_url = "#{@base_url}/elink.fcgi?dbfrom=pubmed&db=pubmed&#{additional_params}"
      @refs_link_name = "pubmed_pubmed_refs"
      @cited_link_name = "pubmed_pubmed_citedin"

      @xml_idtype = 'pubmed'
      @db_idtype = 'pmid'

      @xml_element_data = 'PubmedData'
      @xml_element_citation = 'MedlineCitation'
      @xml_element_bookdata = 'PubmedBookData'
      @xml_element_root = 'PubmedArticleSet'
      @xml_element_root_article = 'PubmedArticle'
      @xml_element_root_book = 'PubmedBookArticle'
    end

    def self.max_pages_to_scrape
      (ENV['PUBMED_MAX_PAGES'] || '10').to_i
    end
    
    def self.results_per_page
      (ENV['PUBMED_RESULTS_PER_PAGE'] || '100').to_i
    end

    def self.client_tool_name
      ENV['PUBMED_CLIENT_TOOL_NAME']
    end

    def self.client_tool_email
      ENV['PUBMED_CLIENT_TOOL_EMAIL']
    end
  end
end
