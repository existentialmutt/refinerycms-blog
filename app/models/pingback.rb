require 'net/http'
require 'uri'
class Pingback < ActiveRecord::Base

  belongs_to :post, :class_name => 'BlogPost', :foreign_key => 'blog_post_id'

  #data validations
  validates :blog_post_id, :presence => true
  validates :source_uri, :presence => true, :uniqueness => {:scope => :blog_post_id}

  # Process an incoming ping request and return the status code if appropriate
  def self.ping(source_uri, target_uri)
    # get the blog post by parsing the target uri and create a pingback
    # debugger
    if target_uri =~ /http:\/\/#{Rails.application.routes.default_url_options[:host]}\/blog\/(.+)/
      target_post = BlogPost.find($1)
      pingback = Pingback.new(:source_uri => source_uri, :post => target_post)
    end


    # validate the pingback and return appropriate error codes if invalid
    return [32, "Target Post could not be found"] unless pingback
    return [48, "Pingback already exists for this source and target"] unless pingback.source_uri_is_unique_for_this_post?
    begin
      # get the source content
      response = Net::HTTP.get_response URI.parse(source_uri)
      # debugger
      #parse it for links to us
      unless target_post.html_links_here?(response.body)
        return [17, "Source URI doesn't link to Target"]
      end
      
      #extract the title and add it to the pingback
      parsed = Nokogiri::HTML(response.body)
      pingback.title = parsed.at_css('title').content
    rescue SocketError, Net::HTTPError => e
      return [16, "Source URI could not be fetched"]
    end

    #save the pingback
    return [0, "Pingback not registered"] unless pingback.save
    return [nil, "#{target_uri} registered pingback from #{source_uri}"]
  end



  def source_uri_is_unique_for_this_post?
    if Pingback.find_by_source_uri_and_blog_post_id source_uri, blog_post_id
      false
    else
      true
    end
  end

  
end
