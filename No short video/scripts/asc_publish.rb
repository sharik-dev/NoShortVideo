# Fiche App Store Connect par l'API directe — textes, captures iPhone 6,5",
# build, notes de revue, soumission. Aucune gem : JWT ES256 fait avec OpenSSL.
#
#   set -a; source ~/.config/ios-testflight-cicd/config.env; set +a
#   ruby scripts/asc_publish.rb meta     # nom, sous-titre, description, mots-clés…
#   ruby scripts/asc_publish.rb shots    # remplace les captures APP_IPHONE_65
#   ruby scripts/asc_publish.rb submit   # attache le build, notes, soumet
#
# Pourquoi pas `deliver` : avec `overwrite_screenshots` il vide *tous* les jeux
# de captures des langues qu'il touche, iPad compris — et les captures iPad de
# cette app ne se régénèrent pas. Ici on ne remplace que le 6,5".
require "openssl"
require "base64"
require "json"
require "net/http"
require "digest"

APP_ID = "6760180650"
ROOT = File.expand_path("..", __dir__)
META = File.join(ROOT, "fastlane/metadata")
SHOTS = File.join(ROOT, "store-screenshots/out3d/iphone65")
LOCALES = { "en-US" => "en", "fr-FR" => "fr" }

def b64(s) = Base64.urlsafe_encode64(s).delete("=")

def token
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_P8_PATH")))
  header  = b64({alg: "ES256", kid: ENV.fetch("ASC_KEY_ID"), typ: "JWT"}.to_json)
  payload = b64({iss: ENV.fetch("ASC_ISSUER_ID"), exp: Time.now.to_i + 1200, aud: "appstoreconnect-v1"}.to_json)
  der = key.sign(OpenSSL::Digest.new("SHA256"), "#{header}.#{payload}")
  r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  "#{header}.#{payload}.#{b64(r + s)}"
end
TOK = token

def api(method, path, body = nil)
  uri = URI(path.start_with?("http") ? path : "https://api.appstoreconnect.apple.com/v1/#{path}")
  req = Net::HTTP.const_get(method.capitalize).new(uri, "Authorization" => "Bearer #{TOK}",
                                                        "Content-Type" => "application/json")
  req.body = body.to_json if body
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  abort("#{method} #{path} → HTTP #{res.code}\n#{res.body}") unless res.code.to_i.between?(200, 299)
  res.body.to_s.empty? ? {} : JSON.parse(res.body)
end
def get(path) = api(:get, path)

def text(locale, name)
  f = File.join(META, locale, "#{name}.txt")
  File.exist?(f) ? File.read(f).strip : nil
end

# La version encore modifiable (la plus récente), et son appInfo modifiable.
def version = get("apps/#{APP_ID}/appStoreVersions?limit=1")["data"].first
def edit_app_info
  get("apps/#{APP_ID}/appInfos")["data"].find { |i| i["attributes"]["appStoreState"] != "READY_FOR_SALE" }
end

def meta
  info = edit_app_info or abort("Aucun appInfo modifiable")
  get("appInfos/#{info['id']}/appInfoLocalizations")["data"].each do |l|
    loc = l["attributes"]["locale"]; next unless LOCALES.key?(loc)
    api(:patch, "appInfoLocalizations/#{l['id']}", data: { type: "appInfoLocalizations", id: l["id"],
        attributes: { name: text(loc, "name"), subtitle: text(loc, "subtitle") } })
    puts "#{loc}: nom + sous-titre"
  end
  get("appStoreVersions/#{version['id']}/appStoreVersionLocalizations")["data"].each do |l|
    loc = l["attributes"]["locale"]; next unless LOCALES.key?(loc)
    api(:patch, "appStoreVersionLocalizations/#{l['id']}", data: { type: "appStoreVersionLocalizations", id: l["id"],
        attributes: { description: text(loc, "description"), keywords: text(loc, "keywords"),
                      promotionalText: text(loc, "promotional_text"), whatsNew: text(loc, "release_notes") } })
    puts "#{loc}: description, mots-clés, promo, nouveautés"
  end
end

def upload_shot(set_id, file)
  data = File.binread(file)
  res = api(:post, "appScreenshots", data: { type: "appScreenshots",
            attributes: { fileName: File.basename(file), fileSize: data.bytesize },
            relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } } } })
  shot = res["data"]
  shot["attributes"]["uploadOperations"].each do |op|
    uri = URI(op["url"])
    req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
    op["requestHeaders"].each { |h| req[h["name"]] = h["value"] }
    req.body = data.byteslice(op["offset"], op["length"])
    r = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    abort("upload #{file} → HTTP #{r.code}") unless r.code.to_i.between?(200, 299)
  end
  api(:patch, "appScreenshots/#{shot['id']}", data: { type: "appScreenshots", id: shot["id"],
      attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(data) } })
end

def shots
  get("appStoreVersions/#{version['id']}/appStoreVersionLocalizations")["data"].each do |l|
    loc = l["attributes"]["locale"]; lang = LOCALES[loc] or next
    sets = get("appStoreVersionLocalizations/#{l['id']}/appScreenshotSets")["data"]
    set = sets.find { |s| s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_65" }
    set ||= api(:post, "appScreenshotSets", data: { type: "appScreenshotSets",
                attributes: { screenshotDisplayType: "APP_IPHONE_65" },
                relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: l["id"] } } } })["data"]
    get("appScreenshotSets/#{set['id']}/appScreenshots")["data"].each { |s| api(:delete, "appScreenshots/#{s['id']}") }
    files = Dir[File.join(SHOTS, lang, "*.png")].sort
    files.each { |f| upload_shot(set["id"], f) }
    puts "#{loc}: #{files.size} captures 6,5\""
  end
end

def submit(build_number)
  v = version
  build = get("builds?filter[app]=#{APP_ID}&filter[version]=#{build_number}")["data"].first
  abort("Build #{build_number} introuvable") unless build
  state = build["attributes"]["processingState"]
  abort("Build #{build_number} pas prêt (#{state})") unless state == "VALID"
  if build["attributes"]["usesNonExemptEncryption"].nil?
    api(:patch, "builds/#{build['id']}", data: { type: "builds", id: build["id"],
        attributes: { usesNonExemptEncryption: false } })
  end
  api(:patch, "appStoreVersions/#{v['id']}/relationships/build", data: { type: "builds", id: build["id"] })
  puts "build #{build_number} attaché à #{v['attributes']['versionString']}"

  notes = File.read(File.join(META, "review_notes.txt")).strip
  detail = get("appStoreVersions/#{v['id']}/appStoreReviewDetail")["data"]
  api(:patch, "appStoreReviewDetails/#{detail['id']}", data: { type: "appStoreReviewDetails", id: detail["id"],
      attributes: { notes: notes, demoAccountRequired: false } })
  puts "notes de revue écrites"

  # Une version rejetée garde sa soumission en UNRESOLVED_ISSUES : on la
  # renvoie telle quelle. Sinon, nouvelle soumission avec la version dedans.
  sub = get("apps/#{APP_ID}/reviewSubmissions?filter[platform]=IOS&limit=10")["data"]
          .find { |s| %w[UNRESOLVED_ISSUES READY_FOR_REVIEW].include?(s["attributes"]["state"]) }
  if sub
    # Sans ça, l'élément rejeté bloque le renvoi : « appStoreVersions … is
    # not in valid state », alors que la version elle-même est prête.
    get("reviewSubmissions/#{sub['id']}/items")["data"].each do |i|
      next unless i["attributes"]["state"] == "REJECTED"
      api(:patch, "reviewSubmissionItems/#{i['id']}", data: { type: "reviewSubmissionItems", id: i["id"],
          attributes: { resolved: true } })
    end
  else
    sub = api(:post, "reviewSubmissions", data: { type: "reviewSubmissions", attributes: { platform: "IOS" },
              relationships: { app: { data: { type: "apps", id: APP_ID } } } })["data"]
    api(:post, "reviewSubmissionItems", data: { type: "reviewSubmissionItems",
        relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub["id"] } },
                         appStoreVersion: { data: { type: "appStoreVersions", id: v["id"] } } } })
  end
  api(:patch, "reviewSubmissions/#{sub['id']}", data: { type: "reviewSubmissions", id: sub["id"],
      attributes: { submitted: true } })
  puts "soumis pour examen"
end

case ARGV[0]
when "meta" then meta
when "shots" then shots
when "submit" then submit(ARGV[1] || abort("numéro de build ?"))
else abort("usage : asc_publish.rb meta|shots|submit <build>")
end
