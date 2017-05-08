module RayyanScrapers
  class PubMedHealthScraper < PubMedScraper
    def initialize
      super
      @base_url = 'http://www.ncbi.nlm.nih.gov/pubmedhealth'
      @search_url = "#{@base_url}/s/full_text_reviews_medrev"
      @detail_url = @base_url
      @pubmed_detail_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml"

      @logger.debug "PubMedHealth scraper initialized"
    end

    def create_search_url(page)
      char = (?a.ord + page - 1).chr
      "#{@search_url}/#{char}"
    end
    
    def get_start_page
      url = create_search_url(1)
      page = @agent.get url
      Nokogiri::HTML.parse(page.body, URI.escape(url))
    end

    def self.max_pages_to_scrape
      26
    end
    
    def process_list_page(page)
      begin
        page.url  # parsed html 
      rescue
        page = Nokogiri::HTML.parse(page.body, page.uri.to_s)
      end
      
      @logger.info("Processing list page with URL: #{page.url}")

      new_items_found = false # don't stop before max_pages

      items = page/'//ul[@class="resultList"]/li/a'
  #    pline "Found #{items.length} items in page", true
      items.each do |anchor|
        
        pmhid = anchor['href'].match(/PMH[\d]+/)[0]
        link = "#{@detail_url}/#{pmhid}"
        title = anchor.text
        
        @logger.info "Got result with id #{pmhid} and link #{link} with title #{title}"
        
  #      pline "  Item #{@curr_property} of #{@total}..."
        # get detailed info

        begin
          article = Article.find_by_url(link)
          if article.nil?
            new_items_found = true
            article = process_pmh_detail_page(@agent.get(link), pmhid, title, link)
            yield article, true
          else
            yield article, false
          end
        rescue => exception
          @logger.error "Error processing #{link}:"
          @logger.error exception
          @logger.error exception.backtrace.join("\n")
        end
        @curr_property = @curr_property + 1
      end
      new_items_found
    end
    
    def extract_pmh_abstracts(doc, mArticle)
      (doc/'//div[@class="body-content whole_rhythm"]/div[@id!=""]').each do |abstract|
        #@logger.debug "Found abstract: #{abstract} with h4: #{abstract.at('./h4')} and text: #{abstract.text}"
        label = ScraperBase.node_text(abstract, './h4')
        content = ScraperBase.node_text(abstract, './p')
        unless label.nil? or content.nil?
          mArticle.abstracts.build  :label => label.gsub(/:/, ''),
                                    :category => abstract['id'],
                                    :content => content
        end
      end
    end
    
    def process_pmh_detail_page(page, pmhid, title, link)
      pmid = ScraperBase.node_text(page, '//a[@title="PubMed record of this title"]')
      
      if pmid.blank?
        @logger.warn "No PMID record for #{pmhid}"
        doc = Nokogiri::HTML.parse(page.body, page.uri.to_s)
        mArticle = Article.new
        mArticle.source = @source
        mArticle.sid = pmhid
        mArticle.title = title
        mArticle.publication_types << PublicationType.where(name: "Book").first_or_create
        extract_pmh_abstracts doc, mArticle
      else
        pmlink = "#{@pubmed_detail_url}&id=#{pmid}"
        @logger.debug "Now processing PMID #{pmid} with url #{pmlink}"
        mArticle = process_detail_page(@agent.get(pmlink), pmid)
      end
      mArticle.url = link
      mArticle.save
      mArticle
    end 
  end
end