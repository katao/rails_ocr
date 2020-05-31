require 'base64'
require 'json'
require 'net/https'
require 'rubygems'
require 'RMagick'

IMAGE_FILE = ARGV[0]

# Google Cloud Vision APIのキー
API_KEY = ''
API_URL = "https://vision.googleapis.com/v1/images:annotate?key=#{API_KEY}"

def get_base64(file, images)
  pdf = Magick::Image.read(file) do
    self.quality = 100
    self.density = 200
  end
  pdf[0].write("pdf_to_img.jpg")

  original = Magick::Image.read('pdf_to_img.jpg').first
  image_list = []
  images.each do |image|
    key = image[0]
    size = image[1]
    crop_image = original.crop(size[0], size[1], size[2], size[3])
    crop_image.write("#{key}.jpg")
    image_list << "#{key}.jpg"
  end
  image = Magick::ImageList.new(image_list[0], image_list[1], image_list[2], image_list[3], image_list[4], image_list[5], image_list[6], image_list[7])
  image = image.append(true)
  image.write("ocr.jpg")
  base64_image = Base64.strict_encode64(File.new("ocr.jpg", 'rb').read)
  return base64_image
end

def get_ocr(content_json)
  # APIリクエスト用のJSONパラメータの組み立て
  body = {
    requests: [{
      image: content_json,
      features: [
        {
          type: 'DOCUMENT_TEXT_DETECTION'
        }
      ],
      imageContext: {
        languageHints: ["jp-t-i0-handwrit"]
      }
    }]
  }.to_json

  # Google Cloud Vision APIにリクエスト投げる
  uri = URI.parse(API_URL)
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request["Content-Type"] = "application/json"
  response = https.request(request, body).body
end

def trim_str(text)
  user = {}
  non_use = 0
  set_text = 'location'
  texts = text.split("\n")
  texts.each_with_index do |line, id|
    if set_text == "location"
      # location
      user[:location] = {}
      if line =~ /水道|所在地|水退|所住地/
        next
      else
        address = line
      end
      #号 を区切り
      location = line.split('号')
      user[:location][:address] = "#{location[0]}号"
      user[:location][:room] = location[1]
      set_text = 'building'
      next
    end

    if set_text == "building"
      # address_detailからの時の動き確認
      user[:location][:building] = nil
      set_text = 'customer_id'
      unless line =~ /\A[0-9]+\z/
        user[:location][:building] = line
        next
      end
    end

    if set_text == "customer_id"
      if line =~ /お客様番号/
        next
      else
        user['customer_id'] = line
      end
      set_text = 'exchange_id'
      next
    end

    if set_text == 'exchange_id'
      if line =~ /番号|担|当/
        next
      else
        user['exchange_id'] = line.gsub(/[\s　]/,"")
      end
      set_text = 'name'
      next
    end

    if set_text == 'name'
      if line =~ /お客さま名/
        user[:name] = {}
        user[:name][:kana] = line.gsub(/[\s　]/,"").gsub(/お客さま名|「/,"")
        next
      else
        user[:name][:kanji] = line.gsub(/、/,"")
      end
      set_text = 'tel'
      next
    end

    if set_text == 'tel'
      line = line.gsub(/[\s　]/,"")
      if /^0/ =~ line
        user['tel'] = line
      else
        user['tel'] = line.slice(1, 100)
      end
      set_text = 'pipe_type'
      next
    end

    if set_text == 'pipe_type'
      user['pipe_type'] = line
      set_text = 'pipe_size'
      next
    end

    if set_text == 'pipe_size'
      user['pipe_size'] = line
    end
  end
  return user
end

crops = {
    "location" => [100, 300, 625, 65],
    "building" => [730, 345, 425, 50],
    "customer_id" => [360, 145, 270, 50],
    "exchange_id" => [100, 245, 420, 55],
    "name" => [100, 360, 460, 65],
    "tel" => [735, 395, 400, 35],
    "pipe_type" => [310, 550, 85, 45],
    "pipe_size" => [415, 550, 75, 45],
  }

if URI.regexp.match(IMAGE_FILE).nil?
  base64_image = get_base64(IMAGE_FILE, crops)
  content_json = { content: base64_image }
else
  content_json = { source: { imageUri: IMAGE_FILE } }
end

response = get_ocr(content_json)
request = JSON[response].to_a
if request[0][1][0]["error"]
  puts request[0][1][0]["error"]["message"]
elsif request[0][1][0]["fullTextAnnotation"]
  user = trim_str(request[0][1][0]["fullTextAnnotation"]["text"])
end

puts user
return user
