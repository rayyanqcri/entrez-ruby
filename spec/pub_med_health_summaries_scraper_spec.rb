require 'spec_helper'

include RayyanScrapers

describe PubMedHealthSummariesScraper do
  let(:scraper) { PubMedHealthSummariesScraper.new("query") }

  describe ".initialize" do
    it "assigns @search_url" do
      expect(scraper.instance_variable_get(:@search_url)).to eq("http://www.ncbi.nlm.nih.gov/pubmedhealth/s/executive_summaries_medrev")
    end
  end
end
