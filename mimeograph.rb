require 'sinatra'
require 'sidekiq'
require 'sidekiq-failures'
require 'redis'
require 'pdfkit'
require 'rest_client'
require 'fog'

post '/generate_pdf_from_url' do
  GeneratePdfFromUrl.perform_async(params["url"], params["callback_url"])
end

get '/ping' do
  "pong"
end

PDFKit.configure do |config|
  config.wkhtmltopdf = [settings.root, 'bin', 'wkhtmltopdf-amd64'].join('/') if settings.production?
  config.default_options[:load_error_handling] = 'ignore'
end

class GeneratePdfFromUrl
  include Sidekiq::Worker
  sidekiq_options :queue => :pdf_generation, :timeout => 300, :retry => false, :backtrace => true

  def perform(url, callback_url)
    if file = PdfGenerator.generate_pdf_with_wkhtmltopdf(url) || PdfGenerator.generate_pdf_with_phantom(url)
      connection = Fog::Storage.new({:provider => 'AWS', :aws_access_key_id => ENV['AWS_ACCESS_KEY'], :aws_secret_access_key => ENV['AWS_SECRET_ACCESS_KEY']})
      bucket = connection.directories.get('mimeograph')
      aws_file = bucket.files.create(
        :key    => "#{SecureRandom.hex}.pdf",
        :body   => file,
        :public => true
      )
      RestClient.put callback_url, :status => "success", :url => aws_file.public_url
    else
      RestClient.put callback_url, :status => "failure"
    end
  end
end

class PdfGenerator
  def self.generate_pdf_with_wkhtmltopdf(url)
    kit = PDFKit.new(url)
    begin
      Timeout.timeout(120) do
        Thread.new{ kit.to_file("#{settings.root}/tmp/#{SecureRandom.hex}.pdf")}.value
      end
    rescue Timeout::Error => e
      false
    end
  end

  def self.generate_pdf_with_phantom(url)
    pdf_path = "#{settings.root}/tmp/#{SecureRandom.hex}.pdf"
    begin
      Timeout.timeout(20) do
        Thread.new{ `phantomjs lib/rasterize.js '#{url}' '#{pdf_path}'`}.value
      end
      File.open(pdf_path)
    rescue Timeout::Error => e
      false
    end
  end
end
