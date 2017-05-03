namespace :nihfulltext do

  desc "Scrape all refs for all PMC NIH fulltexts that have PMID"
  task :getfulltext_refs => :environment do
    nih = Source.find_by_name 'NIH Fulltext'
  end

  desc "Update refs_count for all DARE reviews"
  task :update_refs_count_for_dare, [:dir]  => :environment  do |t, args|
    iterator = DirIterator.new args[:dir]
    iterator.iterate do |file|
      xml = Nokogiri::XML.parse(File.read(file), file)
      mArticle = Article.find_by_url "http://localhost:8000/fromNIH/DARE/#{file}"
      unless mArticle.nil?
        mArticle.refs_count = xml.xpath("count(/article/back/ref-list/ref)")
        raise "Could not save article at #{file}" unless mArticle.save
      else
        raise "No entry for #{file}!"
      end
    end
  end

  # call example: rake nihfulltext:update_section_titles[path/to/DARE]
  desc "Update truncated section titles for all reviews"
  task :update_section_titles, [:dir]  => :environment  do |t, args|
    dir = args[:dir]
    iterator = DirIterator.new dir
    source = dir.split('/').last
    iterator.iterate do |file|
      xml = Nokogiri::XML.parse(File.read(file), file)
      mArticle = Article.find_by_url "http://localhost:8000/fromNIH/#{source}/#{file}"
      unless mArticle.nil?
        pid = file.split('.').first
        if pid.start_with? "PMC"
          article = xml.at '/article'
          NihFulltextScraper.update_section_titles article, mArticle, './body/sec', 'body'
        elsif pid.start_with? "PMH"
          article = xml.at '/book-part'
          chapter_id = (ScraperBase.node_text article, './book-part-meta/elocation-id') || 'chapter'
          NihFulltextScraper.update_section_titles article, mArticle, './body', chapter_id
        else
          puts "Unknown XML format for PID #{pid} with url #{mArticle.url}"
        end
      else
        raise "No entry for #{file}!"
      end
    end
  end

  desc "Detect questions in section titles"
  task :detect_questions_in_section_titles => :environment do
    qwords = %w(what when why where which who whether how do does did is are will shall would should don't doesn't didn't isn't ain't aren't won't wouldn't shouldn't)
    sections = Section.where("title is not null and title != ''")
    total = sections.count
    pbar = ProgressBar.new(total)
    sections.each do |section|
      section.title.split(/[,;\.]/).map(&:strip).each do |sentence|
        if sentence.include?('?') || sentence.strip != '' && qwords.include?(sentence.split(/\s+/).first.downcase)
          section.question = true
        end
      end
      section.save
      pbar.increment!
    end
  end  

  desc "Detect questions in paragraphs"
  task :detect_questions_in_paragraphs => :environment do
    qwords = %w(what when why where which who whether how do does did is are will shall would should don't doesn't didn't isn't ain't aren't won't wouldn't shouldn't)
    paragraphs = Paragraph.where("html is not null and html != ''")
    total = paragraphs.count
    pbar = ProgressBar.new(total)
    paragraphs.each do |paragraph|
      paragraph.text.split(/[,;\.]/).map(&:strip).each do |sentence|
        if sentence.include?('?') || sentence.strip != '' && qwords.include?(sentence.split(/\s+/).first.downcase)
          paragraph.question = true
        end
      end
      paragraph.save
      pbar.increment!
    end
  end  

  desc "Detect key questions in section titles"
  task :detect_key_questions_in_section_titles => :environment do
    # TODO: NEED TO SEARCH FOR PLURAL FORMS AND GET SUB-SECTIONS
    sections = Section.where(
      "label ~* 'key\\s*question' " \
      "or title||'.' ~* '^((summary|update).*){0,1}key\\s*question\\W' " \
      "or title ~* '\\(key\\s*question.*\\)' " \
      "or title||'.' ~* 'research\\s*question\\W'")
    total = sections.count
    pbar = ProgressBar.new(total)
    sections.each do |section|
      section.keyquestion = true
      section.save
      pbar.increment!
    end
  end  

  desc "Fetch and Extract PubMed set (CT fulltexts) from PubMed online server"
  task :fetch_pubtypes_for_CTs, [:dir]  => :environment  do |t, args|
    articles = Article
      .joins(:article_ids)
      .where("url like '%PUBMED%'")
      .where("article_ids.idtype = 'pmid'")
      .select("articles.*, article_ids.value as pmid")
    total = articles.count
    scraper = PubMedScraper.new nil
    pbar = ProgressBar.new(total)
    # fetch to get publication types/mesh
    scraper.fetch_and_parse_article_list(articles, {keyphrases: 1, pubtypes: 1, idtypes: 1}) do |article|
      pbar.increment!
    end
  end

  desc "Recover CTs that lost their PMIDs after initial scraper testing"
  task :recover_CTs_with_no_pmids, [:dir]  => :environment  do |t, args|
    dir = args[:dir]
    # find articles
    articles = Article.find_by_sql("
      select * from articles where url like '%PUBMED%'
      except 
      select a.*
      from articles a, article_ids ai
      where a.id = ai.article_id
      and a.url like '%PUBMED%'
      and ai.idtype = 'pmid';
      ")
    total = articles.count

    # recover pmids from XML sources
    puts "Recovering PMIDs from XML sources and fetching MeSH/PubTypes:"
    scraper = PubMedScraper.new nil
    pbar = ProgressBar.new(total)
    articles.each do |article|
      file = "#{dir}/#{article.sid}.nxml"
      xml = Nokogiri::XML.parse(File.read(file), file)
      idtypes = NihFulltextScraper.extract_idtypes(xml, article, '/article/front/article-meta/article-id[@pub-id-type="pmid"]')
      scraper.fetch_and_parse_detail_page(idtypes.first, article, {keyphrases: 1, pubtypes: 1})
      begin
        article.save
      rescue => exception
        puts exception
        puts exception.backtrace.join("\n")
      end
      pbar.increment!
    end
  end

  #articles = Article.where(:id => ids).joins("left outer join article_ids on article_ids.article_id = articles.id and article_ids.idtype = 'pmid'").select("articles.*, COALESCE(article_ids.value, case articles.source_id when 1 then articles.sid else null end) as pmid")

  desc "Scrape arbitrary article ids from PubMed separated by -"
  task :pubmed_scrape_arbitrary, [:ids]  => :environment  do |t, args|
    ids = args[:ids].split('-')
    # I use this weird outer join because a pmid may exist in article_ids.value or articles.sid if articles.source_id = 1
    # TODO: CHECK AGAIN 
    articles = Article.where(:id => ids)
      .joins("left outer join article_ids on article_ids.article_id = articles.id and article_ids.idtype = 'pmid'")
      .select("articles.*, COALESCE(article_ids.value, case articles.source_id when 1 then articles.sid else null end) as pmid")
    puts "Found #{articles.length} articles"
    scraper = PubMedScraper.new nil
    pbar = ProgressBar.new(articles.length)
    scraper.fetch_and_parse_article_list(articles) do |article|
      pbar.increment!
    end
  end
  
  desc "testing typhoeus"
  task :testing_typhoeus  => :environment  do |t, args|
    hydra = Typhoeus::Hydra.new(:max_concurrency => 10)
    ids = %w(23586057 23585969 23585904 23585903 23585875)
    ids.each {|id|
      req = Typhoeus::Request.new("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id=#{id}",
        headers: {"User-Agent"=>"Mozilla/5.0"})
      req.on_complete do |response|
        puts "request for #{id} returned #{response.code} in time #{response.time} and body size #{response.body.length}"
      end
      hydra.queue(req)
    }
    hydra.run
  end

  desc "Fetch references for all fulltext DARE reviews "
  task :fetch_review_references, [:start_by_id, :idlist]  => :environment  do |t, args|
    start_by_id = args[:start_by_id]
    idlist = args[:idlist]
    idlist = idlist.split('-').map{|id| id.to_i} if idlist
    # get articles
    articles = Article
      .joins(:article_ids)
      .where("url like '%DARE%'")
      .where("article_ids.idtype = 'pmid'")
      .select("articles.*, article_ids.value as pmid")
      .order("articles.id")
    # filter articles
    articles = articles.where("articles.id >= ?", start_by_id) unless start_by_id.blank?
    articles = articles.where("articles.id in (?)", idlist) if idlist && idlist.class == Array && idlist.length > 0
    total = articles.count
    puts "Found #{total} articles to fetch references for"
    scraper = PubMedScraper.new articles
    scraper.scrape true
  end

  desc "Recover deleted PMH Online reviews that had source_id = 1 (PubMed)"
  task :recover_deleted_pmh_online_reviews  => :environment  do |t, args|
    pmids = %w(21155197 21834196 21634073 21155200 21204323 20722131 22379634 22457884 21089246 20722127 20480924 21901868 22876380 22624177 22238805 22220322 22091473 20722137 21370514 22279637 21678630 20704041 21977520 21155203 21834198 20480927 22359775 22514802 21204322 22206106 21328802 20722166 21155209 22420012 22624178 20722148 22787688 22191110 23115813 21348048 21796830 22132426 21834188 21834171 20722152 21796831 20722161 21542545 21595100 21155213 20704053 21089245 20722171 21089237 23230575 21028757 20704042 20704040 20722173 20722133 20722164 21595124 22420013 21796824 23193611 20722167 20722145 22439155 20722142 20722162 20704044 20704045 22812019 21563329 20704039 22741187 22091471 22741186 20704048 21413194 21028756 20704052 20704038 21290640 22319804 20704036 22696783 21698845 20704037 21834186 23230574 20704056 20496364 22132427 20722172 22259825 22206108 20722116 22536621 20722125 20722174 22299185 21155205 22220325 20722139 22319805 21834193 21977519 21678631 22696775 22091470 22259826 21089241 21834190 22132431 22132433 21348046 21370515 21678632 22497032 21089253 22259823 20496442 22132432 21977550 21089250 22319806 21977547 21452460 21089244 21834194 21348045 21678625 22073418 21595121 21089248 20496447 21542548 20496451 22420008 21089251 21089252 20496453 23166955 21309139 20496456 21678627 20496106 21089254 22624163 21089236 22696776 21678624 22299184 20722175 22259824 21938797 23035318 22479722 23236649 22206107 22536620 20722141 21155202 22457883 22439156 21938863 23035275 20722169 21563330 20722157 21938862 22420011 21796832 22439159 22220321 20722120 21510026 20722140 21938799 21155214 22299183 21250397 21656972 20722153 20722154 21155207 23035276 22206109 21595122 21595101 21834195 20722146 20722144 21656970 23256217 20704057 20722128 22319808 22787689 22049569 22720332 22876370 22834016 21834197 23016161 22171401 22439157 22420009 22876372 22812020 22091472 22171400 22624162 21290636 22379659 20722130 21735563 20722176 22132434 21155208 23213666 22319807 22993868 22220324 23256228 22031959 20722149 23270006 22171385 22206114 21309138 22896859 22497033 21735564 21834191 21595123 21977523 21155212 22675737 21290638 22132428 22649799 23256219 22479719 23256218 21542547 20722165 20722138 20722129 20722119 20722158 21542544 20722170 21089238 22876371 22439158 21155210 21678626 23016162 22536622 22916369 21155206 23236638 21290635 22574339 21834189 22574340 21834192 22993867 21089235 21155198 21290639 22973584 21698844 21155201 22191109 21155204 21656971 21542543 23193627 21542542 21938798 23115814 23016160 22553885 22696777 21473024 22649800 20704055 22171386 21698847 20722159 21413195 22536611 20704054 22536619 21834185 22400139 21698846 21452461 21698848 21850778 22279636 22720337 21938859 21938860 21678628 22220323 21938861 21290637 21834187)
   
    puts "Recovering #{pmids.length} articles..." 
    scraper = PubMedScraper.new nil
    pbar = ProgressBar.new(pmids.length)
    scraper.fetch_and_parse_pmid_list(pmids) do |article|
      pbar.increment!
    end
  end

  desc "Interactively label section titles as keyquestions or non-keyquestions"
  task :int_label_sections_as_keyquestions  => :environment  do |t, args|
    t0 = Time.now
    answered = 0
    skipped = 0
    similar_answered = 0
    Signal.trap("INT") do 
      tdiff = Time.now - t0
      tmin = (tdiff / 60).floor; tsec = (tdiff - tmin * 60).round
      print "\rThanks for your time, here are some numbers:\n"
      puts "Time spent: #{tmin} minutes & #{tsec} seconds"
      puts "Answered: #{answered} questions"
      puts "Automatically answered: #{similar_answered} similar questions"
      puts "Skipped: #{skipped} questions"
      total_kq = Section.where(:keyquestion => true).count
      total_nkq = Section.where(:nonkeyquestion => true).count
      distinct_kq = Section.where(:keyquestion => true).count("distinct title")
      distinct_nkq = Section.where(:nonkeyquestion => true).count("distinct title")
      puts "Total/Distinct Key Questions: #{total_kq}/#{distinct_kq}"
      puts "Total/Distinct Non-Key Questions: #{total_nkq}/#{distinct_nkq}"
      exit 0
    end
    while 1 do
      section = Section.where(:keyquestion => false).where(:nonkeyquestion => false)
        .where("title != '' and title is not null")
        .includes(:paragraphs)
        .order("RANDOM()") #postgres only, use rand() for mysql
        .first

      mark_section = Proc.new {|section, keyquestion|
        section.keyquestion = keyquestion
        section.nonkeyquestion = !keyquestion
        section.save
        similar = Section.where(:title => section.title)
        similar_count = similar.count - 1
        if similar_count > 0
          puts "Found #{similar_count} similar section titles, marking them as well"
          similar.update_all("keyquestion = #{keyquestion}, nonkeyquestion = #{!keyquestion}")
          similar_answered += similar_count
        end
        answered += 1
      }

      ask_user = Proc.new {|full_body|
        puts "......................................................."
        prefix = full_body ? "Repeating section" : "Section"
        puts "#{prefix} #{section.id}: #{section.label_with_title}".red
        body = full_body ? section.body : "#{section.body[0..256]}..."
        puts body.green
        puts "......................................................."
        empty_action = full_body ? "skip" : "show more details"
        puts "Is this a Key Question? [y/n/Enter to #{empty_action}/Ctrl+C to exit]: "
        ans = STDIN.gets.chomp
        if ans == 'y'
          mark_section.call(section, true)
        elsif ans == 'n'
          mark_section.call(section, false)
        elsif full_body
          puts "Skipped, better safe than sorry!"
          skipped += 1
        else
          ask_user.call(true)
        end
      }

      ask_user.call(false)
    end
  end

  desc "Parse section types, indexed attribute and ref-list"
  task :parse_section_types_and_more, [:dir]  => :environment  do |t, args|
    dir = args[:dir]
    source = dir.split('/').last
    iterator = DirIterator.new dir
    iterator.iterate do |file|
      xml = Nokogiri::XML.parse(File.read(file), file)
      mArticle = Article.find_by_url "http://localhost:8000/fromNIH/#{source}/#{file}"
      unless mArticle.nil?
        pid = file.split('.').first
        if pid.start_with? "PMC"
          article = xml.at '/article'
          NihFulltextScraper.update_sections_more_details article, mArticle, './body/sec', 'body'
        elsif pid.start_with? "PMH"
          article = xml.at '/book-part'
          chapter_id = (ScraperBase.node_text article, './book-part-meta/elocation-id') || 'chapter'
          NihFulltextScraper.update_sections_more_details article, mArticle, './body', chapter_id
        else
          puts "Unknown XML format for PID #{pid} with url #{mArticle.url}"
        end
      else
        raise "No entry for #{file}!"
      end
    end
  end

  desc "Append articles to searches for DARE references"
  task :append_articles_to_searches_for_DARE_references => :environment do |t, args|
    raise 'this proved to be 2x slower than inserting records directly from db and reindexing all'
    search = Search.find 980190988
    refs = Article.find_by_sql("
      select distinct a2.*
      from articles a, article_references ar, articles a2
      where a.id = ar.article_id and ar.reference_id = a2.id
      and a.url like '%DARE%' order by a2.id;
    ")
    pbar = ProgressBar.new(refs.length)
    refs.each do |a|
      a.searches << search unless a.searches.map(&:id).include? search.id
      raise "Error saving article with id #{a.id}" unless a.save
      pbar.increment!
    end
  end

  desc "Retrieve articles based on a directory containing fetched pmids relative to the writable directory"
  task :pubmed_scrape_arbitrary_directory, [:dir]  => :environment do |t, args|
    dir = args[:dir]
    scraper = PubMedScraper.new nil, dir
    iterator = DirIterator.new Rails.root.join(ENV['WRITABLE_DIR']).join(dir)
    mPubtype = PublicationType.where(name: "PubMed Filtered Systematic Review").first_or_create
    iterator.iterate do |file|
      pmid = file.match(/.*pubmed-([0-9]+).html/)[1]
      raise "No PMID found in file name: #{file}, aborting" unless pmid
      scraper.process_detail_page(pmid) do |article|
        article.publication_types << mPubtype
        raise "Error saving article" unless article.save
      end
    end
  end
end
