require 'benchmark'
require_relative 'magic_xml'

def create_deep_xml(depth)
  return "content" if depth == 0
  XML.new(:tag, "before", create_deep_xml(depth - 1), "after")
end

def create_wide_xml(count)
  contents = []
  count.times do
    contents << "string "
    contents << ""
  end
  XML.new(:root, *contents)
end

def create_mixed_xml(count, depth)
    return "content" if depth == 0
    contents = []
    count.times do
        contents << "s"
        contents << create_mixed_xml(count, depth - 1) if count > 0
    end
    XML.new(:tag, *contents)
end

ITERATIONS = 5

Benchmark.bm(25) do |x|
  x.report("deep xml (500) x#{ITERATIONS}") do
    ITERATIONS.times do
      deep_xml = create_deep_xml(500)
      deep_xml.normalize!
    end
  end

  x.report("wide xml (20000) x#{ITERATIONS}") do
    ITERATIONS.times do
      wide_xml = create_wide_xml(20000)
      wide_xml.normalize!
    end
  end

  x.report("already normalized x#{ITERATIONS}") do
    already_normalized = XML.new(:root, "normalized content", XML.new(:child, "more content"))
    ITERATIONS.times do
      already_normalized.normalize!
    end
  end

  x.report("mixed xml (6^6) x#{ITERATIONS}") do
    ITERATIONS.times do
      mixed_xml = create_mixed_xml(6, 6)
      mixed_xml.normalize!
    end
  end
end
