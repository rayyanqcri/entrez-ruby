module RayyanScrapers
  class PubMedScraper < EntrezScraper
    def initialize(query, content_dir = 'pubmed-contents', log_file = 'pubmed.log')
      super(query, content_dir, log_file)

      additional_params = "tool=rayyan&email=tickets@rayyan.uservoice.com"

      @base_url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils'
      @search_url = "#{@base_url}/esearch.fcgi?db=pubmed&#{additional_params}"
      @detail_url = "#{@base_url}/efetch.fcgi?db=pubmed&retmode=xml&#{additional_params}"
      @detail_friendly_url = "https://www.ncbi.nlm.nih.gov/pubmed/"
      @refs_url = "#{@base_url}/elink.fcgi?dbfrom=pubmed&db=pubmed&#{additional_params}"
      @refs_link_name = "pubmed_pubmed_refs"
      @cited_link_name = "pubmed_pubmed_citedin"

      @source = Source.find_by_name 'PubMed'
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
      ENV['PUBMED_MAX_PAGES'].to_i
    end
    
    def self.results_per_page
      ENV['PUBMED_RESULTS_PER_PAGE'].to_i
      # max on pubmed is 100,000
    end

    def process_article_detail_page(xml, mArticle, extraction_fields)
      extraction_fields = DEFAULT_EXTRACTION_FIELDS if extraction_fields.nil?
      article_xml = xml/"./#{@xml_element_citation}/Article"
      super(xml, article_xml, mArticle, extraction_fields)
      PubMedScraper.extract_journal_info article_xml, mArticle if extraction_fields[:journal]
    end

    def self.extract_journal_info(xml, mArticle)
      journal = xml/'./Journal'
      issn = (journal/'./ISSN').text
      
      mArticle.journal = Journal.where(issn: issn).first_or_initialize do |j|
        j.title = (journal/'./Title').text
        j.abbreviation = (journal/'./ISOAbbreviation').text
      end

      mArticle.jvolume = (journal/'./JournalIssue/Volume').text
      mArticle.jissue = (journal/'./JournalIssue/Issue').text
      mArticle.pagination = (xml/'./Pagination/MedlinePgn').text

      jdate = EntrezScraper.extract_date(journal, './JournalIssue/PubDate')
      if jdate.nil?
        begin
          jdate = (journal/'./JournalIssue/PubDate/MedlineDate').text.to_s
          year = jdate.split.first
          month = jdate.split.last.split('-').first
          jdate = ScraperBase.to_date year, month
        rescue
          jdate = nil
        end
      end
      mArticle.jcreated_at = jdate

      # insert venue information
      mArticle.venue = Venue.where(venueType: "JOURNAL", title: mArticle.journal.title).first_or_initialize
    end
  end
end
