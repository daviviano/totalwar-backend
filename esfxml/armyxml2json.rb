#!/usr/bin/env ruby

require 'nokogiri'
require 'json'
require 'fileutils'

class EsfParser
  def initialize(xml_string)
    @doc = Nokogiri::XML(xml_string)
  end

  def to_json
    root = @doc.root
    result = parse_node(root)
    JSON.pretty_generate(result)
  end

  private

  def parse_node(node)
    return nil if node.nil?
    
    # Special boolean tags
    return false if node.name == 'no'
    return true if node.name == 'yes'

    # Handle specialized types by attribute
    case node['type']
    when 'MILITARY_FORCE'
      return parse_military_force(node)
    when 'ARMY'
      return parse_army(node)
    when 'NAVY'
      return parse_navy(node)
    end

    # Handle simple named tags (like <naval_key> or <unit_history>)
    if !['rec', 'ary', 'land_unit'].include?(node.name) && node.elements.empty?
      val = node.text.strip
      return val.empty? ? nil : val
    end

    # Handle tags by element name
    case node.name
    when 'rec', 'ary'
      return parse_container(node)
    when 'land_unit'
      return parse_attributes(node)
    end
    
    # Last resort for text nodes
    if node.text?
      text = node.text.strip
      return text.empty? ? nil : text
    end
    
    parse_container(node)
  end

  def parse_container(node)
    # Special collection for units
    if node['type'] == 'UNITS_ARRAY'
      units = []
      # Extract land units
      node.xpath('.//land_unit').each do |unit|
        units << parse_attributes(unit)
      end
      # Extract naval units
      node.xpath('.//rec[@type="NAVAL_UNIT"]').each do |unit|
        units << parse_node(unit)
      end
      return units
    end

    data = {}
    node.children.each do |child|
      next if child.text? && child.text.strip.empty?
      next if child.comment?

      child_data = parse_node(child)
      next if child_data.nil?
      
      # Determine key: use type if available, otherwise tag name
      key = child['type'] ? child['type'].downcase : child.name
      next if key.nil? || key.empty? || key == 'text'

      if data.key?(key)
        data[key] = [data[key]] unless data[key].is_a?(Array)
        data[key] << child_data
      else
        data[key] = child_data
      end
    end
    
    if node['type']
      return { node['type'].downcase => data } if node == @doc.root
      return data
    end
    data
  end

  def parse_military_force(node)
    values = node.xpath('./u').map(&:text).map(&:to_i)
    {
      "army_id" => values[0],
      "character_id" => values[1]
    }
  end

  def parse_army(node)
    mf_node = node.at_xpath('./rec[@type="MILITARY_FORCE"]')
    military_force = parse_node(mf_node)

    units_node = node.at_xpath('./ary[@type="UNITS_ARRAY"]')
    units_array = parse_node(units_node)

    footer_i_tags = node.xpath('./i').map(&:text).map(&:to_i)
    footer_u_tags = node.xpath('./u').map(&:text).map(&:to_i)
    
    # Use generic parse for siege status or specific logic
    under_siege = node.at_xpath('./no') ? false : true

    {
      "military_force" => military_force,
      "units_array" => units_array,
      "meta_data" => {
        "army_id_check" => footer_i_tags[0],
        "army_in_building_slot_id" => footer_u_tags[0],
        "under_siege" => under_siege,
        "escorting_ship_id" => footer_u_tags[1] || 0
      }
    }
  end

  def parse_navy(node)
    mf_node = node.at_xpath('./rec[@type="MILITARY_FORCE"]')
    military_force = parse_node(mf_node)

    units_node = node.at_xpath('./ary[@type="UNITS_ARRAY"]')
    units_array = parse_node(units_node)

    # Naval footer mapping
    footer_u_tags = node.xpath('./u').map(&:text).map(&:to_i)
    
    {
      "military_force" => military_force,
      "units_array" => units_array,
      "meta_data" => {
        "army_id_in_ship" => footer_u_tags[0],
        "unknown_val" => footer_u_tags[1]
      }
    }
  end

  def parse_attributes(node)
    data = {}
    node.attributes.each do |k, v|
      val = v.value
      if val.match?(/^-?\d+$/)
        val = val.to_i 
      end
      data[k] = val
    end
    data
  end
end

def aggregate_armies(source_dir, target_file, verbose = false)
  return unless Dir.exist?(source_dir)
  target_name = File.basename(target_file)
  
  groups = Dir.children(source_dir).each_with_object([]) do |file, list|
    next unless file.end_with?('.json') && file != target_name
    
    begin
      file_path = File.join(source_dir, file)
      content = JSON.parse(IO.read(file_path))
      
      if content['army_array']
        # Aggregate both 'army' and 'navy' types
        ['army', 'navy'].each do |type|
          if data = content['army_array'][type]
            if data.is_a?(Array)
              data.each { |item| list << { "file" => file, "type" => type }.merge(item) }
            else
              list << { "file" => file, "type" => type }.merge(data)
            end
          end
        end
      end
    rescue => e
      puts "Error aggregating #{file}: #{e.message}" if verbose
    end
  end

  unless groups.empty?
    File.write(target_file, JSON.pretty_generate(groups))
    puts "Aggregated #{groups.length} groups to #{target_file}" if verbose
  end
end

if __FILE__ == $0
  verbose = false
  if ARGV[0] == "--verbose"
    verbose = true
    ARGV.shift
  end

  if ARGV.length == 2
    xml_path = ARGV[0]
    json_path = ARGV[1]

    unless File.exist?(xml_path)
      puts "Error: Input file #{xml_path} not found."
      exit 1
    end

    xml_string = File.read(xml_path)
    parser = EsfParser.new(xml_string)
    File.write(json_path, parser.to_json)
    
    # Update aggregate
    output_dir = File.dirname(json_path)
    final_file = File.join(output_dir, "army_final.json")
    aggregate_armies(output_dir, final_file, verbose)
  end

  if ARGV[0] == "--aggregate"
    aggregate_armies(ARGV[1], ARGV[2], verbose)
  end
end
