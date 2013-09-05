usage       'create-flyer eventnode outputdir'
aliases     :cf
summary     'creates svg for flyer'
description 'Create SVG file with content of given event'


class CreateFlyer < ::Nanoc::CLI::CommandRunner
  require 'rqrcode_png'

  # Monkey-patch qr generator
  module RQRCodePNG
    class Sequence
      def border_width()
        # No boundary around image
        0
      end
    end
  end

  def getQR(data)
    qr = nil
    size = 7
    while (!qr)
      begin
        qr = RQRCode::QRCode.new(data, :size => size, :level => :l)
      rescue RQRCode::QRCodeRunTimeError
        qr = nil
        size = size + 1
      end
    end
    qr
  end

  def run
    # Check arguments
    if arguments.length!=2
      puts command.help
      exit 1
    end
    # Get node, check type
    self.load_site
    nodename = sanitize_path(arguments[0])
    event = self.site.items[nodename]
    if !event
      puts "Node #{nodename} not found"
      exit 1
    end
    if !event[:kind]=='event'
      puts "Node #{nodename} is not an event"
      exit 1
    end
    # Collect data
    merge_item_location_data(event[:location], self.site.items['/_data/locations/'].attributes)
    calculate_to_date(event)
    self.site.compile
    title = event[:title]
    date = event[:startdate]
    speakers = event[:speakers].map { |s| if s[:affiliation] then "#{s[:name]} (#{s[:affiliation]})" else s[:name] end }
    text = Nokogiri::HTML(event.compiled_content)
    text = text.content.gsub(/\n+/,"\n")
    location_name = [event[:location][:name]]
    if (event[:location][:details])
      location_name << event[:location][:details]
    end
    location_address = []
    if (event[:location][:strasse])
      location_address << event[:location][:strasse]
    end
    if (event[:location][:ort])
      if (event[:location][:plz])
        location_address << "#{event[:location][:plz]} #{event[:location][:ort]}"
      else
        location_address << event[:location][:ort]
      end
    end
    location_geo = if (event[:location][:lon])
                     "N #{event[:location][:lon]} E #{event[:location][:lat]}"
                   else
                     ""
                   end
    calendar_items = self.site.items.select do |i|
      (i[:kind]=='event') && (i[:startdate].to_datetime>event[:startdate].to_datetime) && !i.identifier.start_with?('/_data/stammtisch/')
    end.sort { |a,b| a[:startdate].to_datetime <=> b[:startdate].to_datetime }
    calendar = calendar_items[0..5].map do |i|
      if i[:startdate].instance_of?(Date)
        "#{i[:startdate].strftime("%d.%m.%Y")}: #{i[:title]}"
      else
        "#{i[:startdate].strftime("%d.%m.%Y, %H:%M")}h: #{i[:title]}"
      end
    end
    vevent = []
    vevent << "BEGIN:VEVENT"
    vevent << "SUMMARY:#{event[:title]}"
    vevent << "DTSTART:#{event[:startdate].getutc.strftime("%Y%m%dT%H%M%SZ")}"
    vevent << "DTEND:#{event[:enddate].getutc.strftime("%Y%m%dT%H%M%SZ")}"
    vevent << "LOCATION:#{location_name.join(", ")}"
    vevent << "DESCRIPTION:Weitere Infos: #{site.config[:base_url]}#{event.path()}"
    vevent << "END:VEVENT"
    # Generate qr code
    qr_img = getQR(vevent.join("\n")).to_img
    # Read template
    file = File.open(self.site.items['/_data/aushang/'].raw_filename(), "r:UTF-8")
    template = file.read
    file.close()
    # Replace in template
    template.gsub!('${title}', title)
    template.gsub!('${date}', date.strftime("%d.%m.%Y, %H:%M"))
    template.gsub!('${speakers}', speakers.join(', '))
    template.gsub!('${location.name}', location_name.join(", "))
    template.gsub!('${location.address}', location_address.join(", "))
    template.gsub!('${location.geo}', location_geo)
    template.gsub!('${qrcode}', "#{qr_img.to_data_url}")
    for i in 0..5 do
      template.gsub!("${calendar.#{i}}", calendar[i] || "")
    end
    # Output
    File.open("#{arguments[1]}/aushang.svg", 'w:UTF-8') {|f| f.write(template) }
  end
end

runner CreateFlyer

