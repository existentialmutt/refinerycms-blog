require 'acts-as-taggable-on'
require 'seo_meta'
require 'nokogiri'
# for pingback
require 'net/http'
require 'uri'
require 'xmlrpc/client'

class BlogPost < ActiveRecord::Base

  after_save do |blog_post|
  # send pingbacks to links in the body
    logger.info "Executing Pingback callback"
    parsed = Nokogiri::HTML(blog_post.body)
    links = parsed.css('a[href]')
    links.each do |link|
      logger.warn "Sending pingback to #{link['href']}"
      blog_post.send_pingback(link['href'])
    end
  end

  is_seo_meta if self.table_exists?

  default_scope :order => 'published_at DESC'
  #.first & .last will be reversed -- consider a with_exclusive_scope on these?

  belongs_to :author, :class_name => 'User', :foreign_key => :user_id, :readonly => true

  has_many :comments, :class_name => 'BlogComment', :dependent => :destroy
  acts_as_taggable

  has_many :categorizations, :dependent => :destroy
  has_many :categories, :through => :categorizations, :source => :blog_category

  has_many :pingbacks, :order => "created_at ASC"

  acts_as_indexed :fields => [:title, :body]

  validates :title, :presence => true, :uniqueness => true
  validates :body,  :presence => true

  has_friendly_id :friendly_id_source, :use_slug => true,
                  :default_locale => (::Refinery::I18n.default_frontend_locale rescue :en),
                  :approximate_ascii => RefinerySetting.find_or_set(:approximate_ascii, false, :scoping => 'blog'),
                  :strip_non_ascii => RefinerySetting.find_or_set(:strip_non_ascii, false, :scoping => 'blog')

  scope :by_archive, lambda { |archive_date|
    where(['published_at between ? and ?', archive_date.beginning_of_month, archive_date.end_of_month])
  }

  scope :by_year, lambda { |archive_year|
    where(['published_at between ? and ?', archive_year.beginning_of_year, archive_year.end_of_year])
  }

  scope :all_previous, lambda { where(['published_at <= ?', Time.now.beginning_of_month]) }

  scope :live, lambda { where( "published_at <= ? and draft = ?", Time.now, false) }

  scope :previous, lambda { |i| where(["published_at < ? and draft = ?", i.published_at, false]).limit(1) }
  # next is now in << self

  def next
    BlogPost.next(self).first
  end

  def prev
    BlogPost.previous(self).first
  end

  def live?
    !draft and published_at <= Time.now
  end

  def category_ids=(ids)
    self.categories = ids.reject{|id| id.blank?}.collect {|c_id|
      BlogCategory.find(c_id.to_i) rescue nil
    }.compact
  end

  def friendly_id_source
    custom_url.present? ? custom_url : title
  end

  class << self
    def next current_record
      self.send(:with_exclusive_scope) do
        where(["published_at > ? and draft = ?", current_record.published_at, false]).order("published_at ASC")
      end
    end

    def comments_allowed?
      RefinerySetting.find_or_set(:comments_allowed, true, {
        :scoping => 'blog'
      })
    end
    
    def teasers_enabled?
      RefinerySetting.find_or_set(:teasers_enabled, true, {
        :scoping => 'blog'
      })
    end
    
    def teaser_enabled_toggle!
      currently = RefinerySetting.find_or_set(:teasers_enabled, true, {
        :scoping => 'blog'
      })
      RefinerySetting.set(:teasers_enabled, {:value => !currently, :scoping => 'blog'})
    end

    def uncategorized
      BlogPost.live.reject { |p| p.categories.any? }
    end
  end

  module ShareThis
    DEFAULT_KEY = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

    class << self
      def key
        RefinerySetting.find_or_set(:share_this_key, BlogPost::ShareThis::DEFAULT_KEY, {
          :scoping => 'blog'
        })
      end

      def enabled?
        key = BlogPost::ShareThis.key
        key.present? and key != BlogPost::ShareThis::DEFAULT_KEY
      end
    end
  end

  # does the given html include a link to this blog post?
  def html_links_here?(html)
    parsed = Nokogiri::HTML(html)
      parsed.css('a[href]').each do |link|
        if link['href'] == Rails.application.routes.url_helpers.blog_post_url(self)
          return true
        end
      end
      return false
  end

  def send_pingback(their_url)
    response = Net::HTTP.get_response URI.parse(their_url)

    #Look for the Pingback server in the HTTP header
    if response['X-Pingback'] 
      pingback_url = URI.parse response['X-Pingback']
    else
      # Look for the Pingback server in the response body
      parsed = Nokogiri::HTML(response.body)
      if node = parsed.at_css('link[rel=pingback]')
        pingback_url = URI.parse node['href']
      end
    end
    # handle_asynchronously :send_pingback

    #send the XML-RPC request if we have a url
    if pingback_url
      logger.info "sending pingback for #{their_url} from #{url} using server url #{pingback_url}" 
      rpc_client = XMLRPC::Client.new pingback_url.host, pingback_url.path, pingback_url.port, nil, nil, nil, nil, nil, 300000
      begin
        result = rpc_client.call("pingback.ping", their_url, url) 
        Delayed::Worker.logger.warn "Pingback to #{their_url} succeeded with #{result}"
      rescue RuntimeError, SocketError, XMLRPC::FaultException => e
        Delayed::Worker.logger.warn "Pingback to #{their_url} failed with #{e.message}"
      end
    else
      Delayed::Worker.logger.warn "No pingback server found for #{their_url}"
    end
  end
  handle_asynchronously :send_pingback

  def url
    Rails.application.routes.url_helpers.blog_post_url(self)
  end

end
