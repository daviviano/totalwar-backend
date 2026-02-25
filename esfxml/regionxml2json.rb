#!/usr/bin/env ruby

require 'nokogiri'
require 'json'
require 'fileutils'

class RegionParser
  def initialize(file_path)
    @doc = Nokogiri::XML(File.read(file_path))
  end

  def to_json
    root = @doc.at_xpath('/rec[@type="REGION"]')
    return { error: "Not a REGION file" } unless root

    # We filter children to ignore blank text/whitespace nodes
    @children = root.children.reject { |c| c.text? && c.text.strip.empty? || c.comment? }
    @cursor = 0

    parse_schema
  end

  private

  # This pulls the current node and advances the cursor
  def next_node
    node = @children[@cursor]
    @cursor += 1
    node
  end

  # Helper to parse specific array types found in ESF
  def parse_u4_ary(node)
    node.text.split.map(&:to_i)
  end

  def parse_bool_ary(node)
    node.text.split.map { |v| v == '1' }
  end

  def parse_v2(node)
    { x: node['x'].to_f, y: node['y'].to_f }
  end

  # The Schema Mapper
  # We consume nodes in the exact order they appear in the ESF XML
  def parse_schema
    {
      type: "REGION",
      region_name: next_node.text,                           # <s> name
      population_path: next_node['path'],                    # <xml_include>
      traits: (next_node; {}),                               # <traits> 
      
      region_slot_manager: parse_slot_manager(next_node),    # <rec type="REGION_SLOT_MANAGER">
      region_id: next_node.text.to_i,                        # <i> ID
      settlement_path: next_node['path'],                    # <xml_include> settlement
      
      # The block of unlabeled integers/bools
      unknown_val_1: next_node.text.to_i,                    # <u>
      unknown_bool_1: !next_node.name.include?('no'),        # <no/> or <yes/>
      unknown_bool_2: !next_node.name.include?('no'),        # <no/> or <yes/>
      
      # Economy Block
      subsistence_agricultural: next_node.text.to_i,         # <u>
      industrial_wealth_plus: next_node.text.to_i,           # <u>
      industrial_wealth_net: next_node.text.to_i,            # <u> (minus trade losses)
      town_wealth: next_node.text.to_i,                      # <u>
      min_town_wealth: next_node.text.to_i,                  # <u>
      town_wealth_accumulated: next_node.text.to_i,          # <u>
      town_monetary_growth: next_node.text.to_i,             # <i>
      
      unknown_val_2: next_node.text.to_i,                    # <u>
      unknown_val_3: next_node.text.to_i,                    # <u>
      exempt_from_tax: !next_node.name.include?('no'),       # <no/>
      controlling_faction_id: next_node.text.to_i,           # <u>
      
      line_of_sight: parse_line_of_sight(next_node),         # <rec type="LINE_OF_SIGHT">
      
      governor_id: next_node.text.to_i,                      # <u>
      theatre: next_node.text,                               # <s>
      emergent_nation: next_node.text,                       # <s>
      region_rebels: next_node.text,                         # <s>
      region_culture: next_node.text,                        # <s>
      
      region_recruitment_manager: parse_recruitment(next_node), # <rec type="REGION_RECRUITMENT...">
      
      unknown_bool_3: !next_node.name.include?('no'),        # <no/>
      
      # Arrays
      unknown_arrays: [
        parse_u4_ary(next_node),
        parse_u4_ary(next_node),
        parse_u4_ary(next_node),
        parse_u4_ary(next_node)
      ],
      
      bool_array: parse_bool_ary(next_node),                 # <bool_ary>
      int_array: (n = next_node; n.text.empty? ? [] : n.text.split.map(&:to_i)), # <i4_ary>
      
      religious_mission_buildings: (next_node; []), # Consume <ary> 
      forts: (next_node; []),                       # Consume <ary>
    }.tap do |hash|
        # Clean up the simple consumed nodes for the empty arrays above
        # Resource Array (Text content with newlines)
        res_node = next_node 
        hash[:resources_array] = res_node.text.split("\n").map(&:strip).reject(&:empty?)
        
        hash[:latest_construction] = next_node.text          # <s>
        hash[:prestige_when_conquered] = next_node.text.to_i # <u>
        hash[:region_array_identifier] = next_node.text.to_i # <u>
        hash[:loc_onscreen] = next_node.text                 # <loc>
        hash[:unknown_float] = next_node.text.to_f           # <flt>
    end
  end

  def parse_slot_manager(node)
    slots = []
    # Find the array inside
    ary = node.at_xpath('./ary')
    if ary
      ary.xpath('./xml_include').each do |inc|
        slots << inc['path']
      end
    end
    
    roads = node.xpath('./xml_include').map { |x| x['path'] }
    
    {
      slots: slots,
      infrastructure: roads
    }
  end

  def parse_line_of_sight(node)
    return nil unless node
    {
      visible: !node.at_xpath('./no'),
      coordinates: node.xpath('./v2').map { |v| parse_v2(v) },
      quadtree_path: node.at_xpath('./xml_include') ? node.at_xpath('./xml_include')['path'] : nil
    }
  end

  def parse_recruitment(node)
    {
      recruitment_item_array: [], # Simplified for this example
      active: !node.at_xpath('./no'),
      recruitment_id: node.at_xpath('./i') ? node.at_xpath('./i').text.to_i : nil
    }
  end
end

if __FILE__ == $0
  verbose = false
  if ARGV[0] == "--verbose"
    verbose = true
    ARGV.shift
  end

  if ARGV.length != 2
    puts "Usage: ruby regionxml2json.rb [--verbose] <input_xml> <output_json>"
    exit 1
  end

  xml_path = ARGV[0]
  json_path = ARGV[1]

  unless File.exist?(xml_path)
    puts "Error: Input file #{xml_path} not found."
    exit 1
  end

  begin
    parser = RegionParser.new(xml_path)
    json_data = parser.to_json
    File.write(json_path, JSON.pretty_generate(json_data))
  rescue => e
    puts "Error processing #{xml_path}: #{e.message}"
    exit 1
  end
end
