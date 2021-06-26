
# https://blog.lunarlogic.io/2019/managing-tags-in-jekyll-blog-easily/

Jekyll::Hooks.register :posts, :post_write do |post|
  tags = post['tags'].reject { |t| t.empty? }
  tags.each do |tag|
    path = "tags/" + tag_file_basename(tag) + ".md"
    if !File.file?(path)
      raise 'tag file for ' + tag + ' is missing at ' + path
    end
    # generate_tag_file(tag) if !all_existing_tags.include?(tag)
  end
end

def tag_file_basename(tag)
  return tag + ''
end
