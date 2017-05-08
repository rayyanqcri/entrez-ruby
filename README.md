[![Build Status](https://travis-ci.org/rayyanqcri/rayyan-scrapers.svg?branch=master)](https://travis-ci.org/rayyanqcri/rayyan-scrapers)
[![Coverage Status](https://coveralls.io/repos/github/rayyanqcri/rayyan-scrapers/badge.svg?branch=master)](https://coveralls.io/github/rayyanqcri/rayyan-scrapers?branch=master)

# RayyanScrapers

A set of Ruby scrapers (web crawlers) used by [Rayyan](https://rayyan.qcri.org).
It currently supports [PubMed](https://www.ncbi.nlm.nih.gov/pubmed/)
using the [Entrez API](https://www.ncbi.nlm.nih.gov/books/NBK25501/)
but more scrapers can be added easily.

## Installation

Add this line to your application's Gemfile:

    gem 'rayyan-scrapers'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rayyan-scrapers

## Usage

### Topic search

Before doing any topic search using the Entrez API, you must set your tool name and email.
Otherwise, you may get Access Denied errors from the API and your IP address may get blocked completely.
See the configuration section below.

To issue a search query using `PubMedScraper` (ESearch followed by EFetch for results):

    keywords = 'diabetes'
    scraper = RayyanScrapers::PubMedScraper.new
    scraper.search(keywords) do |article, total|
      puts total
      puts article
    end

This will send a query to the ESearch utility with the `keywords` specified.
The `search` method will repeatedly yield control with every resulting article along with the total number found.
This will allow results to be yielded as soon as they are fetched (using the EFetch utility) and parsed
instead of waiting for the whole result set to finish, which may not fit in memory anyway.

The `keywords` parameter can be in one of three formats:

#### String

    keywords = 'diabetes'

This will simply use the specified string as the search criteria.

#### Array of Strings

    keywords = %w(diabetic exercise)

This will search for the `AND` concatenated array (`diabetic AND exercise` in this example).

#### Array of Arrays of Strings

    keywords = [['diabetic', 'type-2 diabetes'], ['exercise', 'physical']]

Each keyword in the second level arrays will be concatenated by `OR`
and the resulting strings will be concatenated with `AND`.
So the above `keywords` will generate this query:

    (diabetic OR type-2 diabetes) AND (exercise OR physical)

### PubMed XML file parsing

If you have downloaded a PubMed XML file of the search results, you can parse it
and get the resulting articles the same way returned from the scraping process.
This is even faster as it involves no remote HTTP activity.

    body = File.read('/path/to/pubmed-results.xml')
    total = RayyanScrapers::PubMedScraper.new.parse_search_results(body) do |article, total|
      puts total
      puts article
    end
    raise 'Unknown XML' if total == 0

The above code will read a file then passes it to the parser. It will yield articles as they are parsed
as in the scraping process. If the returned `total` equals to zero, then either the XML was invalid or empty.

### PubmedXML RayyanFormats plugin

This gem also offers a plugin for [RayyanFormats](https://github.com/rayyanqcri/rayyan-formats-core) for importing Pubmed XML files.
It can be typically added using the standard plugin configuration method:

    RayyanFormats::Base.plugins = [
      # ... others plugins
      RayyanFormats::Plugins::PubmedXML
      # ... others plugins
    ]

Once configured, it will be accepted as a valid format when calling:

    RayyanFormats::Base.import

### Data types

The article objects are of type `RayyanFormats::Target`.
More details on this can be found [here](https://github.com/rayyanqcri/rayyan-formats-core#rayyanformatstarget).
Specifically, the article objects will have these methods (unless otherwise noted, all values are of type `String`):

- `title`: Article/Book title
- `copyright`: Copyright information
- `affiliation`: Main authors affiliation
- `language`: Article original language
- `publisher_name`: Publisher name
- `publisher_location`: Publisher address
- `collection`: Book collection name
- `collection_code`: Book collection code
- `abstracts`: `Array` of abstracts. Each abstract is a `Hash` object with `label`, `category` and `content` fields
- `authors`: `Array` of ordered authors in the format `last name, first name`
- `article_ids`: `Array` of unique article identifiers (DOI, PMID, ...). Each identifier is a `Hash` object with `idtype` and `value` fields
- `publication_types`: `Array` of publication types. For books it will have only 1 type: `Book`
- `keywords`: `Array` of keywords
- `sections`: `Array` of book sections. Each section is a `Hash` object with `code`, `location` and `title` fields
- `journal_title`: Journal title
- `journal_issn`: Journal ISSN
- `journal_abbreviation`: Journal abbreviation
- `jvolume`: Volume number (`Fixnum`)
- `jissue`: Issue number (`Fixnum`)
- `pagination`: Pagination information
- `date_array`: `Array` of date components (e.g. `["2017", "10", "1"]`). Note that the day alone or month+day could be missing


## Configuration

### Tool name and email

Set 2 environment variables before creating the scraper instance (`PubMedScraper.new`).
There are multiple ways to set environment variables in Ruby. Either using command line,
Rails environments.rb, [.env file](https://github.com/bkeepers/dotenv), or through code.

    ENV['PUBMED_CLIENT_TOOL_NAME'] = 'your_tool_name'
    ENV['PUBMED_CLIENT_TOOL_EMAIL'] = 'your_tool_email'

### Limiting results

By default, `PubMedScraper` will scrape up to 10 pages only with 100 results per page.
This makes 1000 maximum results. To change these limits, create 2 new environment variables:

    ENV['PUBMED_MAX_PAGES'] = 100
    ENV['PUBMED_RESULTS_PER_PAGE'] = 1000

This will raise the limit to `100 * 1000 = 100000` results.

### HTTP Parallelism

You can control the parallelism degree by which article details are fetched.
By default, 50 articles are fetched in parallel.
To change this, set the following environment variable before creating the scraper instance:

    ENV['SCRAPERS_MAX_PARALLEL_ARTICLES'] = 100

### Logging

You can specify a logger object to receive various scraper logs in different log levels.

For pure Ruby, use the standard [Logger](http://ruby-doc.org/stdlib-2.1.0/libdoc/logger/rdoc/Logger.html) object:

    require 'logger'
    logger = Logger.new(STDOUT) # or specify a file
    logger.level = Logger::DEBUG # INFO, WARN, ERROR or FATAL

    RayyanScrapers::PubMedScraper.new(logger)

For Rails, you can log to the configured Rails logger:

    RayyanScrapers::PubMedScraper.new(Rails.logger)

### Caching HTTP responses

Usually it is desired to cache HTTP responses for fetched articles (EFetch not ESearch requests).
RayyanScrapers uses [Moneta](https://github.com/minad/moneta)
for a unified interface to dozens of cache store adapters (Memory, File, Memcached, Redis, ActiveRecord, MongoDB, S3, ...)
You pass the cache constructor to the scraper constructor exactly the same way
you use on Moneta. For example, to set a memory cache store:

    moneta_options = [:Memory]
    RayyanScrapers::PubMedScraper.new(logger, moneta_options)

To use a file store:

    moneta_options = [:File, {dir: 'my_cache_dir'}]
    RayyanScrapers::PubMedScraper.new(logger, moneta_options)

If you are using Rails and Dalli Memcached client:

    moneta_options = [:MemcachedDalli, {backend: Rails.cache.dalli}]
    RayyanScrapers::PubMedScraper.new(logger, moneta_options)

All Moneta adapters are documented on its [rubydoc](http://www.rubydoc.info/github/minad/moneta/master/Moneta/Adapters).

## Testing

    rspec

Or

    rake

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
