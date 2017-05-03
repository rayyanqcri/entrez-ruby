require 'spec_helper'

include RayyanScrapers

describe PubMedScraper do
  describe '#initialize' do
    let(:logger) {
      l = Logger.new(STDOUT)
      l.level = Logger::FATAL
      l
    }
    let(:pub_med_scraper) { PubMedScraper.new([], logger) }
    let(:tool_name) { 'rspec_tool_name' }
    let(:tool_email) { 'rspec_tool@email.com' }
    let(:tool_params) { "tool=#{tool_name}&email=#{tool_email}" }

    before {
      ENV['PUBMED_CLIENT_TOOL_NAME'] = tool_name
      ENV['PUBMED_CLIENT_TOOL_EMAIL'] = tool_email
    }

    it "includes client tool information in search_url" do
      expect(pub_med_scraper.instance_variable_get(:@search_url)).to \
        include(tool_params)
    end

    it "includes client tool information in detail_url" do
      expect(pub_med_scraper.instance_variable_get(:@detail_url)).to \
        include(tool_params)
    end

    it "includes client tool information in refs_url" do
      expect(pub_med_scraper.instance_variable_get(:@refs_url)).to \
        include(tool_params)
    end
  end

  describe '.max_pages_to_scrape' do
    before { ENV['PUBMED_MAX_PAGES'] = '100' }

    it {expect(PubMedScraper.max_pages_to_scrape).to eq(100)}
  end

  describe '.results_per_page' do
    before { ENV['PUBMED_RESULTS_PER_PAGE'] = '1000' }

    it {expect(PubMedScraper.results_per_page).to eq(1000)}
  end

end