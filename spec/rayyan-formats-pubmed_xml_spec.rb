require 'spec_helper'

include RayyanScrapers

describe RayyanFormats::Plugins::PubmedXML do
  let(:logger) {
    l = Logger.new(STDOUT)
    l.level = Logger::FATAL
    l
  }
  let(:contents_path) { Pathname.new "spec/support/entrez-contents" }
  let(:pubmed_file) { contents_path.join("pubmed1.xml").to_s  }
  let(:source) { RayyanFormats::Source.new(pubmed_file) }

  before {
    RayyanFormats::Base.logger = logger
    RayyanFormats::Base.plugins = [
      RayyanFormats::Plugins::PubmedXML
    ]
  }

  it "yields correct articles from the PubmedXML plugin" do
    expect{|b|
      RayyanFormats::Base.import(source, &b)
    }.to yield_successive_args(
      [RayyanFormats::Target, 2],
      [RayyanFormats::Target, 2]
    )
  end
end