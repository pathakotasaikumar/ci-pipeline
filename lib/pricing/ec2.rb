require 'net/http'
require 'json'
require 'openssl'

module Pricing
  module EC2
    PRICING_FILE = "#{__dir__}/data/ec2.json"
    PRICING_URL = "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/index.json"

    class << self
      def generate_pricing_file(
        file: PRICING_FILE,
        term: "OnDemand",
        capacity_status: ["Used"],
        regions: ["Asia Pacific (Sydney)"],
        instance_type: [],
        tenancy: [],
        operating_system: [],
        license: [],
        software: []

      )
        instance_pricing = {}

        uri = URI(PRICING_URL)
        req = Net::HTTP::Get.new(uri)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true

        pricing_data = JSON.parse(http.request(req).body)

        # Iterate over pricing data to build up relevant product hashes
        pricing_data["products"].each do |product, spec|
          next unless regions.include? spec["attributes"]["location"] and spec["productFamily"] == "Compute Instance"
          next unless capacity_status.empty? or capacity_status.include? spec["attributes"]["capacitystatus"]
          next unless tenancy.empty? or tenancy.include? spec["attributes"]["tenancy"]
          next unless instance_type.empty? or instance_type.include? spec["attributes"]["instanceType"]
          next unless operating_system.empty? or operating_system.include? spec["attributes"]["operatingSystem"]
          next unless license.empty? or license.include? spec["attributes"]["licenseModel"]
          next unless software.empty? or software.include? spec["attributes"]["preInstalledSw"]

          instance_pricing[product] = {
            "instance_type" => spec["attributes"]["instanceType"].downcase,
            "tenancy" => spec["attributes"]["tenancy"].downcase,
            "operating_system" => spec["attributes"]["operatingSystem"].downcase,
            "license" => spec["attributes"]["licenseModel"].downcase,
            "software" => spec["attributes"]["preInstalledSw"].downcase,
            "region" => spec["attributes"]["location"].downcase
          }
        end

        # iterate over pricing data to add
        pricing_data["terms"][term].each do |product, spec|
          next unless instance_pricing.keys.include? product

          spec.each do |_, offer|
            offer["priceDimensions"].each do |_, dimension|
              instance_pricing[product]["cost"] = dimension["pricePerUnit"]["USD"]
            end
          end
        end

        # Write out culled list of prices to disk
        open(file, "wb") { |f| f.write JSON.pretty_generate(instance_pricing) }
      end

      def price(
        instance_type: nil,
        license: nil,
        operating_system: nil,
        pricing_file: PRICING_FILE,
        region: "asia pacific (sydney)",
        software: nil,
        tenancy: nil
      )
        Log.debug "#{instance_type} #{license} #{operating_system} #{pricing_file} #{region} #{software} #{tenancy}"

        pricing_data = open(pricing_file) { |f| f.read }

        prices = []
        JSON.parse(pricing_data).each do |_, instance_details|
          next unless instance_details["region"] == region or region.nil?
          next unless instance_details["instance_type"] == instance_type or instance_type.nil?
          next unless instance_details["tenancy"] == tenancy or tenancy.nil?
          next unless instance_details["operating_system"] == operating_system or operating_system.nil?
          next unless instance_details["license"] == license or license.nil?
          next unless instance_details["software"] == software or software.nil?

          prices << instance_details["cost"].to_f
          raise "More than one value returned" if prices.size > 1
        end

        return prices.max
      end

      # processes spot pricing value for launch configuration
      # @param spot_alias [String] spot alias value, such as '@ondemand'
      # @param platform [String] target platform, such as :windows, :amazon_linux, :centos or :rhel
      # @param instance_type [String] instance type, such as t2.micro and so on
      # @param tenancy [String] EC2 tenancy type, dedicated or shared
      def process_ec2_spot_price(
        spot_alias:,
        platform:,
        instance_type:,
        tenancy:,
        license: "no license required",
        software: "na"
      )
        raise "Missing a value or alias for SpotPrice" if spot_alias.nil?

        Log.debug "Using spot alias: #{spot_alias}"
        operating_system = _get_spot_price_os(platform: platform)

        Log.debug " - platform: #{platform}"
        Log.debug " - operating_system: #{operating_system}"
        Log.debug " - software: #{software}"
        Log.debug " - license: #{license}"

        Log.debug "Fetching pricing data..."

        spot_max_bid = Pricing::EC2.price(
          operating_system: operating_system,
          instance_type: instance_type,
          license: license,
          tenancy: tenancy == "dedicated" ? "dedicated" : "shared",
          software: software
        )

        Log.debug "Fetched max bid value: #{spot_max_bid}"

        if platform == :rhel or instance_type.match(/t2.|hs1./) or spot_max_bid.nil? or tenancy == "dedicated"
          Log.debug "Unable to set Spot price for #{tenancy} #{instance_type} instance. Using On demand pricing"
          return nil
        end

        case
        when spot_alias.match(/^[-+]?[0-9]*\.?[0-9]+$/)
          spot_bid = spot_alias.to_f
          diff_spot_price =  spot_max_bid - spot_bid

          if diff_spot_price > 0
            Log.debug "SpotPrice requested #{spot_bid} is less than #{spot_max_bid}. Setting bid = USD#{spot_bid}"
            return spot_bid
          else
            Log.debug "SpotPrice requested #{spot_bid} is greater than #{spot_max_bid}. Setting maximum bid = USD#{spot_max_bid}"
            return spot_max_bid
          end
        when spot_alias == "@ondemand"
          Log.debug "SpotPrice requested based on '#{spot_alias}'. Setting maximum bid = USD#{spot_max_bid}"
          return spot_max_bid
        else
          raise "Unknown alias \"#{spot_alias}\" specified for SpotPrice."
        end
      end

      private

      # return operating system name for pricing data
      # @param platform [:Symbol] platform name, such as :windows, ::amazon_linux, :centos or :rhel
      def _get_spot_price_os(platform:)
        case platform
        when :windows
          return "windows"
        when :amazon_linux, :centos
          return "linux"
        when :rhel
          return "rhel"
        else
          raise "Unsupported platform value: #{platform}"
        end
      end
    end
  end
end
