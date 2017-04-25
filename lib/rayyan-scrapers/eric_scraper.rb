module RayyanScrapers
  class EricScraper < ScraperBase
    attr_reader :query

    def initialize(query, content_dir = 'eric-contents')
      super('eric.log', content_dir)
      @base_url = 'http://www.eric.ed.gov/ERICWebPortal'
      @search_url = "#{@base_url}/search/simpleSearch.jsp?searchtype=advanced"
      @detail_url = "#{@base_url}/detail?accno="

      @params = []
      
      base, offset = 0, 0
      query.each do |topic_query|
        topic_query.each_index do |id|
          offset = base + id
          if offset > 0
            if id == 0
              @params << "ERICExtSearch_Operator_#{offset}=and"
            else
              @params << "ERICExtSearch_Operator_#{offset}=or"
            end
          end
          @params << "ERICExtSearch_SearchType_#{offset}=kw"
          keyword = topic_query[id]
          quot = if keyword.include? " " then '"' else '' end
          open_parenth = if id == 0 and topic_query.size > 1 then "(" else "" end
          close_parenth = if id == topic_query.size - 1 and topic_query.size > 1 then ")" else "" end
          term = URI.escape("#{open_parenth}#{quot}#{keyword}#{quot}#{close_parenth}")
          @params << "ERICExtSearch_SearchValue_#{offset}=#{term}"
        end
        base = offset + 1
      end
      
      @query = @params.join("&")
      @logger.debug "ERIC scraper initialized with query #{@query}"
      
  	  @source = Source.find_by_name 'ERIC'
      @stop_on_seen_page = false
    end

    def create_search_url(page)
      page_size = self.class.results_per_page
      start_item = (page - 1) * page_size + 1
      url = "#{@search_url}&newSearch=true&pageSize=#{page_size}&eric_displayStartCount=#{start_item}" \
      "&#{@query}" \
      "&ERICExtSearch_EDEJSearch=elecBoth&_pageLabel=ERICSearchResult" \
      "&ERICExtSearch_PubDate_From=0&ERICExtSearch_PubDate_To=3000" \
      "&ERICExtSearch_SearchCount=0"
      @logger.debug "Created search url: #{url}"
      url
    end
    
    def get_start_page
      url = create_search_url(1)
      page = @agent.get url
      #page.save_as "result-list-1.html"
      Nokogiri::HTML.parse(page.body, URI.escape(url))
    end

    def self.max_pages_to_scrape
      2 # TODO THIS IS ONLY A TEST, IN PRODUCTION SHOULD BE A BIGGER NUMBER
    end
    
    def self.results_per_page
      50 #max on eric is 50
    end

    def total_pages(page)
      begin
        results_text = ScraperBase.node_text(page, '//*[@id="contentContainer"]/h1/text()')
        n = results_text.gsub(/\D/, "")
        @logger.info("Found total of #{n} results")
        n
      rescue
    	  'Unknown'
      end
    end
    
    def get_next_page_link(page)
      begin
        create_search_url @curr_page
      rescue
        nil
      end
    end

    def process_list_page(page)
      begin
        page.url  # parsed html 
      rescue
        page = Nokogiri::HTML.parse(page.body, page.uri.to_s)
      end
      
      @logger.info("Processing list page with URL: #{page.url}")

      new_items_found = nil

      items = page/'//table[@class="tblSearchResult"]//tr[1]/td[1]/p/a'
  #    pline "Found #{items.length} items in page", true
      items.each do |anchor|
        
        new_items_found = false if new_items_found.nil? 
      
        link = anchor['href']
        ericid = link.match(/accno=([^&]+)/)[1]
        
        @logger.info "Got result with id #{ericid}"
        
  #      pline "  Item #{@curr_property} of #{@total}..."
        # get detailed info

        begin
          article = Article.find_by_sid(ericid)
          if article.nil?
            new_items_found = true
            article = process_detail_page(@agent.get(link), ericid)
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
    
    def save_journal(article, issn, title)
      if issn == false
        mJournal = Journal.find_by_title title
        issn = nil
      else
        mJournal = Journal.find_by_issn issn
      end
      
      if mJournal.nil?
        article.build_journal :issn => issn, 
                                :title => title
      else
        article.journal = mJournal
      end
    end
    
    def process_detail_page(page, ericid)
      doc = Nokogiri::HTML.parse(page.body, page.uri.to_s)

      mArticle = Article.new
      mArticle.source = @source
      mArticle.url = "#{@detail_url}#{ericid}"
      mArticle.sid = ericid

      issn = nil
      journal_title = nil
      
      (doc/'//table[@class="nestedTablePadded"]//tr').each do |tr|
        key = ScraperBase.node_text(tr, './td[1]').gsub(':', '')
        val_node = tr.at './td[2]'
        unless val_node.nil?
          val = val_node.text
          case key.downcase
          when 'title'
            mArticle.title = val
          when 'authors'
            (val_node/'./a').each do |author|
              authorArr = author.text.split(',')
              lastname = authorArr[0].strip
              firstname = authorArr[1].strip
              
              mAuthor = (Author.where :firstname => firstname, :lastname => lastname).first
              if mAuthor.nil?
                mArticle.authors.build :firstname => firstname, 
                                        :lastname => lastname
              else
                mArticle.authors << mAuthor
              end
            end
          when 'descriptors', 'source'
            #journal_info = val.match(/([^,]+),\s*v([\d]+)\s*n([\d]+)\s*p([\d\-,\s]+)\s*([\w]+)\s*([\d]+)/)
            @logger.debug "journal info line: #{val}"
            m = val.match(/v([\d]+)/)
            mArticle.jvolume, hit = m[1], 1 unless m.nil?
            m = val.match(/n([\d]+)/)
            mArticle.jissue, hit = m[1], 1 unless m.nil?
            m = val.match(/p([\d\-,\s]+)/)
            mArticle.pagination, hit = m[1].strip, 1 unless m.nil?
            m = val.match(/\b([\w]{3})\s*([\d]{4})$/)
            unless m.nil? or m.size != 3
              month, year, hit = m[1], m[2], 1
              mArticle.jcreated_at = ScraperBase.to_date(year, month)
            end
            
            if hit == 1 
              m = val.match(/^([^,]+)/)
              journal_title = if m.nil? then "" else m[0] end
            else
              journal_title = val
            end
            
          when 'publication date' # is needed when not stated in source
            if mArticle.jcreated_at.nil?
              arr = val.split('-')
              if arr.size == 3
                mArticle.jcreated_at = ScraperBase.to_date(*arr) # * explodes arr to args
              end
            end
          when 'pub types'
            val.split(';').each do |pubtype|
              pubtype = pubtype.strip.singularize
              mPubtype = PublicationType.find_by_name(pubtype)
              if mPubtype.nil?
                mArticle.publication_types.build :name => pubtype
              else
                mArticle.publication_types << mPubtype
              end
            end
          when 'abstract'
            mArticle.abstracts.build :content => val
          when 'issn'
            if val.downcase.start_with?('issn-')
              issn = val[5..-1]
            elsif val.downcase != 'n/a'
              issn = val
            else
              issn = false
            end 
            save_journal(mArticle, issn, journal_title)
          when 'languages'
            # TODO: HAVEN'T SEEN ANYTHING BUT English, RAISE WHEN SEEN TO INSPECT
            mArticle.language = val 
            raise "Found non-English article #{val}" unless val == "English"
          when 'direct link'
            #mArticle.url = val
            # TODO: EXTRACT DOI AND OTHERS FROM HERE
          end 
        end
      end
      
      mArticle.save
      page.save_as("#{@content_dir}/eric-#{ericid}.html")
      mArticle
    end

  end
end
