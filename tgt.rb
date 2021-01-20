require 'csv'
require 'gecko-ruby'  #use modded gem with StockAdjustments
require 'yaml'

CREDS = YAML.load(File.read('creds.yaml'))
gecko = Gecko::Client.new(CREDS[:OAUTH_ID], CREDS[:OAUTH_SECRET])
gecko.access_token = OAuth2::AccessToken.new(gecko.oauth_client, CREDS[:API_TOKEN])

MAX_LIMIT = 250 # https://developer.tradegecko.com/docs.html#pagination
START = "2020-01-01"
STOP =  "2020-12-31"

# get all the adjustments
adjustments = []
page = 1
while (next_page = gecko.StockAdjustment.where(created_at_min: START, created_at_max: STOP, page: page, limit: MAX_LIMIT)) != []
  adjustments << next_page
  page += 1
end
adjustments.flatten!

# then all locations and adjustment lineitem ids and the variant info
locations = {}
adj_line_ids = []
adjustments.each do |rec|
  locations[rec.stock_location_id] = true if !locations.has_key? rec.stock_location_id
  adj_line_ids << rec.stock_adjustment_line_item_ids
end
adj_line_ids.flatten!

adj_line_items = {}
variants = {}         # store only keys for later
while adj_line_ids.length > 0
  page = gecko.StockAdjustmentLineItem.where ids: adj_line_ids.shift(MAX_LIMIT)
  page.each do |item| 
    adj_line_items[item.id] = item if !adj_line_items.has_key? item.id 
    variants[item.variant_id] = true if !variants.has_key? item.variant_id
  end
end

variant_ids = variants.keys
while variant_ids.length > 0
  page = gecko.Variant.where( ids: variant_ids.shift(MAX_LIMIT) )
  page.each { |variant| variants[variant.id] = variant if variants[variant.id] == true }
end

# generate the CSV for NS import
headers = [
  'Inventory Adjustment : External ID',
  'Inventory Adjustment : Reference',
  'Inventory Adjustment : Adjustment Location',
  'Inventory Adjustment : Stock Adj. Reason Code (Req)',
  'Inventory Adjustment : Memo',
  'Inventory Adjustment : Date (Req)',
  'Inventory Adjustment Adjustments : Line',
  'Inventory Adjustment Adjustments : Adjust Qty. By (Req)',
  'Inventory Adjustment Adjustments : Item',
]
OUT = CSV.new(STDOUT, headers: headers, write_headers: true,)

adjs = adjustments.dup
while (txn = adjs.pop) != nil
  header = [txn.id] <<
    txn.adjustment_number <<
    txn.stock_location_id <<
    txn.reason_label <<
    txn.reason <<
    txn.created_at.strftime('%d-%b-%Y')
  
  txn.stock_adjustment_line_item_ids.each do |id|
    item = adj_line_items[id]
    OUT << header + [item.position, Integer(item.quantity), variants[item.variant_id].sku]
  end
end