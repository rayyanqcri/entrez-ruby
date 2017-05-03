require 'pathname'
require 'typhoeus'

module RayyanScrapers
  class Stubber
    def self.stubbed_root
      Pathname.new "../../../spec/support/stubbed"
    end

    def self.stub_pubmed(set_id)
      sets = [2, 5, 50]
      raise "set_id argument should be one of #{sets.inspect}" unless sets.include? set_id
      Rails.logger.info "Stubbing PubMed..."
      base_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"

      stub_request_with_file(self.stubbed_root.join("pubmed-search-#{set_id}.xml"),
        Regexp.new(base_url))

    end

    def self.stub_pubmed_details
      Rails.logger.info "Stubbing PubMed details..."
      base_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id="
      DirIterator.new(self.stubbed_root).iterate do |file|
        pmid = file.match(/.*pubmed-([0-9]+).xml/)[1]
        stub_request_with_file(file, "#{base_url}#{pmid}")
      end
    end

    def self.stub_pubmed_refs
      Rails.logger.info "Stubbing PubMed references..."
      base_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/elink.fcgi?dbfrom=pubmed&db=pubmed&id="

      DirIterator.new(self.stubbed_root.join("refs")).iterate do |file|
        pmid = file.match(/.*pubmed-refs-([0-9]+).xml/)[1]
        stub_request_with_file(file, "#{base_url}#{pmid}")
      end
      
      # 100029
      # 1000147
      # 4589401
      # 10029499
      # 10051785
      # 10052380
      # 10052444

    end

    def self.stub_prediction
      allow_any_instance_of(PredictionModelTrainJob).to receive(:run).and_return(nil)
    end

    def self.unstub_prediction
      allow_any_instance_of(PredictionModelTrainJob).to receive(:run).and_call_original
    end

    def self.stub_request_with_file(filename, url)
      stub_request_with_body File.read(filename), url
    end

    def self.stub_request_with_body(body, url)
      response = Typhoeus::Response.new(code: 200, body: body)
      Typhoeus.stub(url).and_return(response)
      response
    end

    def self.stub_request_with_error(code, url)
      response = Typhoeus::Response.new(code: code)
      Typhoeus.stub(url).and_return(response)
      response
    end
  end
end
