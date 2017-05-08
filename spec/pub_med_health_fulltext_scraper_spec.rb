require 'spec_helper'

include RayyanScrapers

describe PubMedHealthFulltextScraper do
  let(:scraper) { PubMedHealthFulltextScraper.new }

  describe ".initialize" do
    it "assigns @search_url" do
      expect(scraper.instance_variable_get(:@search_url)).to eq("http://www.ncbi.nlm.nih.gov/pubmedhealth/s/full_text_reviews_medrev")
    end
  end
end
