# GENERATED VIA SALT -- DO NOT EDIT --
# {% set cfg = salt['mc_project.get_configuration'](cfg) %}
# {% set data = cfg.data %}
# 
# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

import directors;
import std;

# Default backend definition. Set this to point to your content server.
{% for server in data.backends %}
backend {{ server.id }} {
    .host = "{{ server.ip }}";
    {% if data.force_host_header_on_backends %}
    .host_header = "{{ data.domain }}";
    {%endif %}
    .port = "{{ server.port }}";
    .connect_timeout = 5s; .first_byte_timeout = 200s; .between_bytes_timeout = 60s;
    {% if data.probe_backends %}
    .probe = {
        .url = "{{ data.probe_url }}"; 
        .interval = {{ data.probe_interval }}; 
        .timeout = {{ data.probe_timeout }};
        .window = {{ data.probe_window }};
        .threshold = {{ data.probe_thresold }};
    }
    {% endif %}
}
{% endfor %}

sub vcl_init {
    # create round-robin director with all backends
    new lb_default = directors.round_robin();
    {% for server in data.backends %}
    lb_default.add_backend({{ server.id }});
    {% endfor %}
}

acl restricted {
    {% for ip in data.ip_allowed_for_purge %}
    "{{ ip }}";
    {% endfor %}
}

sub vcl_recv {
    # Happens before we check if we have this in cache already.
    #
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.
    # RETURN ACTIONS ########################
    # pipe: never do that
    # pass: transfer to backend, almost transparent mode
    # hash: check internal cache (or pass to backend)
    # lookup: only used in vcl_hash, in vcl_recv it's hash
    # fetch: used in vcl_pass, to make a pass
    # deliver: this has to be used in vcl_backend_response, deliver the cached object
    # esi: ESI-Gate
    # purge : purge cache
    # synth : error case

    # NORMALIZATION OF ACCEPT-ENCODING HEADER
    # either gzip, then deflate, then none
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.({{ data.static_ext }})$") {
            # No point in compressing these
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
           set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate" && req.http.user-agent !~ "MSIE") {
           set req.http.Accept-Encoding = "deflate";
        } else {
           # unkown algorithm
           unset req.http.Accept-Encoding;
        }
    }

    # BACKEND CHOICE
    # Here no filters on if (req.http.host ~ "foo.example.com$") 
    # As we have only one backend
    # CATCH ALL
    set req.backend_hint = lb_default.backend();

    if (! req.http.host) {
        return(synth(400, "No host header, common, HTTP/1.1"));
    }

    # Do not cache these paths and restrict access
    if (req.url ~ "^/phpfpm-status\.php" ||
        {% if data.probe_backends and data.restrict_probe_url_access %}
        req.url ~ "^{{ data.probe_url | replace('.', '\.')}}" ||
        {% endif %}
        req.url ~ "^/nginx-status\.php") {
      if (!client.ip ~ restricted) {
          return(synth(405, "Not Allowed"));
      } else {
          return (pass);
      }
    }

    {% if data.use_drupal_recv %}
    # Drupal specific tasks
    call drupal_recv;
    {% endif %}

    # Remove all cookies that Drupal doesn't need to know about. ANY remaining
    # cookie will cause the request to pass-through to Apache. For the most part
    # we always set the NO_CACHE cookie after any POST request, disabling the
    # Varnish cache temporarily. The session cookie allows all authenticated users
    # to pass through as long as they're logged in.
    if (req.http.Cookie) {
        # a=b; SESS4564645=123; c=d;  NO_CACHE=Y; x=y
        # a=b;SESS4564645=123;c=d;NO_CACHE=Y;x=y
        # a=b; SESS4564645=123;c=d; NO_CACHE=Y;x=y
        # a=b; SESS4564645=123; NO_CACHE=Y
        # SESS4564645=123; NO_CACHE=Y
        # add a ;
        set req.http.Cookie = ";" + req.http.Cookie;
        # remove spaces
        set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
        # add spaces for SESS & NO_CACHE cookies
        # and remove cookies without spaces before the ;
        set req.http.Cookie = regsuball(req.http.Cookie, ";({{ data.keep_cookies }})=", "; \1=");
        set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");
  
        if (req.http.Cookie == "") {
            # If there are no remaining cookies, remove the cookie header. If there
            # aren't any cookie headers, Varnish's default behavior will be to cache
            # the page.
            unset req.http.Cookie;
        #} else {
            # If there is any cookies left (a session or NO_CACHE cookie), do not
            # cache the page. Pass it on to Apache/Nginx directly.
        #    return(pass);
        }
    }

    # purge restrictions
    if (req.method == "PURGE") {
        if (client.ip ~ restricted) {
            return(synth(405,"Not allowed."));
        }
        return (purge);
    }

    if (req.method != "GET" &&
     req.method != "HEAD" &&
     req.method != "PUT" &&
     req.method != "POST" &&
     req.method != "OPTIONS" &&
     req.method != "DELETE") {
       # Non-RFC2616 or CONNECT which is weird, we remove TRACE also.
       return(synth(501, "Not Implemented"));
    }

    if (req.method != "GET" && req.method != "HEAD") {
        # for cache we only deal with GET and HEAD, by default 
        return(pass);
    }

    if (req.http.Authorization || req.http.Cookie) {
        # Not cacheable, by definition
        return(pass);
    }

    # else we do an internal cache check
    # was lookup in previous versions of varnish
    return(hash);
}


{% if data.use_drupal_recv %}
sub drupal_recv {

  {% if data.probe_backends %}
  # ARE WE STILL ALIVE??
  # Use anonymous, cached pages if all backends are down.
  if (!std.healthy(req.backend_hint)) {
    unset req.http.Cookie;
  }
  {% endif %}


  # Static content unique to the theme can be cached
  if (
      (
        (req.url ~ "^/profiles/([^/]*)/themes/")
        || (req.url ~ "^/themes/")
        || (req.url ~ "^/sites/all/libraries/")
        || (req.url ~ "^/sites/([^/]*)/themes/")
        || (req.url ~ "^/misc/")
        || (req.url ~ "^/modules/")
      )
      && req.url ~ "\.({{ data.static_ext }})$") {
         unset req.http.cookie;
  }

  # Do not cache these paths. could be adding ajax things here for example?
  if (req.url ~ "^/admin/build/features") {
       return (pass);
  }

  # Uncomment this to trigger the vcl_error() subroutine, 
  # which will HTML output you some variables
  # return(synth(700, 'debug'));

  # Pipe these paths directly to Nginx for streaming.
  if (req.url ~ "^/batch") {
    return (pass);
  }

  # clean static files from cookies, so that we can cache them all
  if (req.url ~ "^/sites/([^/]*)/files") {
    unset req.http.cookie;
  }
}
{% endif %}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.

    # Allow the backend to serve up stale content if it is responding slowly.
    set beresp.grace = {{ data.grace_period }};

    if (beresp.http.X-No-Cache) {
        set beresp.uncacheable = true;
        return (deliver);
    }

    if (bereq.url ~ "\.({{ data.static_ext }})") {

        # Don't allow static files to set cookies.
        unset beresp.http.set-cookie;

        # Enforce TTL of static files
        set beresp.ttl = {{ data.static_ttl }};

        # Enforce cache control policy
        unset beresp.http.Cache-Control;
        unset beresp.http.expires;
        set beresp.http.Cache-Control = "public, max-age={{ data.static_ttl_browser }}";

    } else {

        # Set a magic marker, this could be cacheable or not
        # but we will use this marker to alter this cacheable behavior
        # for Safari in the deliver phase (and avoid doing it for assets)
        # We do not do it in fetch because this should only be done for one user-agent
        # and the user-agent is not on the cache identifier (hash), so doing it here
        # would store the result in cache for all user agents
        set beresp.http.magicmarker = "1";

    }

    # cache 404 for 60s
    if (beresp.status == 404) {
        set beresp.ttl = 60s;
        set beresp.http.Cache-Control = "max-age=60";
    }

    if (beresp.ttl <= 0s) {
        set beresp.http.X-Cacheable = "NO:Not Cacheable";
        set beresp.uncacheable = true;
        return(deliver);
    }
    if (beresp.http.Set-Cookie) {
        set beresp.http.X-Cacheable = "NO:Not Cacheable setting cookie";
        set beresp.uncacheable = true;
        return(deliver);
    }
    set beresp.http.X-Cacheable = "YES";

    return(deliver);
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.

    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Safari fix (make content uncacheable in browser cache) should apply only
    # on non-assets things, check the magicmarker for that
    if (resp.http.magicmarker) {
        unset resp.http.magicmarker;
        # Safari Fix, @see https://drupal.org/node/1910178 https://drupal.org/node/2147147
        if (req.http.user-agent ~ "Safari" && req.http.user-agent !~ "Chrome") {
          set resp.http.Cache-Control = "no-cache, must-revalidate, post-check=0, pre-check=0";
          unset resp.http.Etag;
          unset resp.http.Expires;
          unset resp.http.Last-Modified;
          set resp.http.age = "0";
        }
    }
}


sub vcl_pipe {
    # A pipe is a dangerous HTTP thing, think smuggling, shared IP per domains, etc
    # better close it soon
    # Avoid pipes like plague
    set req.http.connection = "close";
    return(pipe);
}

sub vcl_hash {
    hash_data(req.url);
    hash_data(req.http.host);
    # BUG: vary accept-encoding seems to be wiped out
    # on some js response, enforce it!
    if (req.http.Accept-Encoding) {
        hash_data(req.http.Accept-Encoding);
    }
    # Include the X-Forward-Proto header, since we want to treat HTTPS
    # requests differently, and make sure this header is always passed
    # properly to the backend server.
    if (req.http.X-Forwarded-Proto) {
        hash_data(req.http.X-Forwarded-Proto);
    }
    return(lookup);
}

sub vcl_hit {
    if (!(obj.ttl>0s)) {
        return(deliver);
    }
    {% if data.probe_backends %}
    if (!std.healthy(req.backend_hint) && (obj.ttl + obj.grace > 0s)) {
    {% else %}
    if (obj.ttl + obj.grace > 0s) {
    {% endif %}
        // object is in grace period
        // backend seems to be quite in a bad mood
        // we will deliver it but this will trigger a background fetch
        return(deliver);
    }
    // fetch & deliver once we get the result
    return(fetch);
}

sub vcl_miss {
    if (req.method == "PURGE") {
      return(synth(404,"Not in cache."));
    }
    return(fetch);
}

