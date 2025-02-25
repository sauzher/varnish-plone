vcl 4.0;
import std;

# configure all backends
backend default {
   .host = BACKEND;
   .port = BACKEND_PORT;
   .connect_timeout = 4s;
   .first_byte_timeout = 300s;
   .between_bytes_timeout  = 60s;
}


sub vcl_init {
    
}

acl purge {
    "localhost";
    "127.0.0.1";
    "172.0.0.0/8";
    "10.0.0.0/8";
    BACKEND;
}

sub vcl_recv {
    set req.backend_hint = default;
    
    if (req.method == "PURGE") {
        # Not from an allowed IP? Then die with an error.
        if (!client.ip ~ purge) {
            return (synth(405, "This IP is not allowed to send PURGE requests."));
        }
        if (req.url ~ "^/@@purgebyid/") {
            ban("obj.http.x-ids-involved ~ #" + regsub(req.url, "^/@@purgebyid/", "") + "#");
            return(synth(200, "Ban added"));
        }
        return(purge);
    }

    if (req.method == "BAN") {
            # Same ACL check as above:
            if (!client.ip ~ purge) {
            return(synth(403, "Not allowed."));
            }
            #ban("req.url ~ " + req.url);
        ban("req.http.host == " + req.http.host +
            " && req.url == " + req.url);
            # Throw a synthetic page so the
            # request won't go to the backend.
            return(synth(200, "Ban added"));
    }

    # Only deal with "normal" types
    if (req.method != "GET" &&
           req.method != "HEAD" &&
           req.method != "PUT" &&
           req.method != "POST" &&
           req.method != "TRACE" &&
           req.method != "OPTIONS" &&
           req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return(pipe);
    }

    # Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
    if (req.method != "GET" && req.method != "HEAD") {
        return(pass);
    }

    if (req.http.Expect) {
        return(pipe);
    }

    if (req.http.If-None-Match && !req.http.If-Modified-Since) {
        return(pass);
    }

    /* Do not cache other authorized content by default */
    if (req.http.Authenticate || req.http.Authorization) {
        return(pass);
    }

    /* cookies for pass */
    if (req.http.Cookie && req.http.Cookie ~ "__ac(|_(name|password|persistent))=") {
        if (req.url ~ "\.(js|css|kss)") {
            unset req.http.cookie;
            return(pipe);
        }
        return(pass);
    }

    /* Cookie whitelist, remove all not in there */
    if (req.http.Cookie) {
        set req.http.Cookie = ";" + req.http.Cookie;
        set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
        set req.http.Cookie = regsuball(req.http.Cookie, ";(statusmessages|__ac|_ZopeId|__cp)=", "; \1=");
        set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");
        if (req.http.Cookie == "") {
            unset req.http.Cookie;
        }
    }

    if (
req.url ~ "/@@search(/?)" ||
req.url ~ "/@@updated_search(/?)" ||
req.url ~ "/search(/?)" ||
        req.url ~ "/livesearch_reply(/?)" ||
        req.url ~ "(.*)(/?)b_start:int=" ||
        req.url ~ "(.*)(/?)tipo_albopretorio=" ||
        req.url ~ "(.*)(\?|&)sezione=" ||
        req.url ~ "(.*)(\?|&)came_from=" ||
        req.url ~ "(.*)(\?|&)next=" ||
        req.url ~ "(.*)(\?|&)anno="
           ) {
        # Normalize the query arguments
        set req.url = std.querysort(req.url);
          # Some generic URL manipulation, useful for all templates that follow
          # First remove the Google Analytics added parameters, useless for our backend
          if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
            set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
            set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
            set req.url = regsub(req.url, "\?&", "?");
            set req.url = regsub(req.url, "\?$", "");
          }

          # Strip hash, server doesn't need it.
          if (req.url ~ "\#") {
            set req.url = regsub(req.url, "\#.*$", "");
          }

          # Strip a trailing ? if it exists
          if (req.url ~ "\?$") {
            set req.url = regsub(req.url, "\?$", "");
          }

      }else{
        set req.url = regsub(req.url, "\?.*", "");
      }

    # Large static files should be piped, so they are delivered directly to the end-user without
    # waiting for Varnish to fully read the file first.

    # TODO: make this configureable.

    if (req.url ~ "^[^?]*\.(mp3,mp4|rar|tar|tgz|gz|wav|zip|pdf|avi)(\?.*)?$") {
        return(pipe);
    }
     if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|mp4|ogg|pdf|avi)$") {
          unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
          set req.http.Accept-Encoding = "gzip";
        } else {
          unset req.http.Accept-Encoding;
        }
      }

    return(hash);
}

sub vcl_pipe {
    
    # By default Connection: close is set on all piped requests, to stop
    # connection reuse from sending future requests directly to the
    # (potentially) wrong backend. If you do want this to happen, you can undo
    # it here.
    # unset bereq.http.connection;

    return(pipe);
}

sub vcl_pass {
    
    return (fetch);
}

sub vcl_hash {
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    return (lookup);
}

sub vcl_purge {
    set req.http.X-purger = "Purged purger";
    return (synth(200, "Purged in purge: "+req.url));
}

sub vcl_hit {
    
     if (req.method == "PURGE") {
        set req.method = "GET";
        set req.http.X-purger = "Purged by hit";
        return(synth(200, "Purged. in hit " + req.url));
    }

    if (obj.ttl >= 0s) {
        // A pure unadultered hit, deliver it
        # normal hit
        return (deliver);
    }

    // fetch & deliver once we get the result
    return (fetch);
}

sub vcl_miss {
    

    if (req.method == "PURGE") {
        set req.method = "GET";
        set req.http.X-purger = "Purged-possibly";
        return(synth(200, "Purged. in miss " + req.url));
    }

    // fetch & deliver once we get the result
    return (fetch);
}

sub vcl_backend_fetch{
    
    return (fetch);
}

sub vcl_backend_response {
    if (bereq.url ~ "(manage_)") {
        set beresp.uncacheable = true;
        return(deliver);
        #return(pass);
    }
    #set beresp.ttl = 1m;
    set beresp.grace = 3h;

    # The object is not cacheable
    if (beresp.http.Set-Cookie) {
        set beresp.http.X-Cacheable = "NO - Set Cookie";
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    } elsif (beresp.http.Cache-Control ~ "private") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=private";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (beresp.http.Surrogate-control ~ "no-store") {
        set beresp.http.X-Cacheable = "NO - Surrogate-control=no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (!beresp.http.Surrogate-Control && beresp.http.Cache-Control ~ "no-cache|no-store") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=no-cache|no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (beresp.http.Vary == "*") {
        set beresp.http.X-Cacheable = "NO - Vary=*";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;


    # ttl handling
    } elsif (beresp.ttl < 0s) {
        set beresp.http.X-Cacheable = "NO - TTL < 0";
        set beresp.uncacheable = true;
    } elsif (beresp.ttl == 0s) {
        set beresp.http.X-Cacheable = "NO - TTL = 0";
        set beresp.uncacheable = true;

    # Varnish determined the object was cacheable
    } else {
        set beresp.http.X-Cacheable = "YES";
    }

    # Do not cache 5xx errors
    if (beresp.status >= 500 && beresp.status < 600) {
        unset beresp.http.Cache-Control;
        set beresp.http.X-Cache = "NOCACHE";
        set beresp.http.Cache-Control = "no-cache, max-age=0, must-revalidate";
        set beresp.ttl = 0s;
        set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        return(deliver);
    }

    # TODO this one is very plone specific and should be removed, not sure if its needed any more
    if (bereq.url ~ "(createObject|@@captcha)") {
        set beresp.uncacheable = true;
        return(deliver);
    }

    return (deliver);
}

sub vcl_deliver {
    set resp.http.grace = req.http.grace;
    unset resp.http.x-ids-involved;

    if (obj.hits > 0) {
         set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    /* Rewrite s-maxage to exclude from intermediary proxies
      (to cache *everywhere*, just use 'max-age' token in the response to avoid
      this override) */
    if (resp.http.Cache-Control ~ "s-maxage") {
        set resp.http.Cache-Control = regsub(resp.http.Cache-Control, "s-maxage=[0-9]+", "s-maxage=0");
    }
    /* Remove proxy-revalidate for intermediary proxies */
    if (resp.http.Cache-Control ~ ", proxy-revalidate") {
        set resp.http.Cache-Control = regsub(resp.http.Cache-Control, ", proxy-revalidate", "");
    }
}

/*
 We can come here "invisibly" with the following errors: 413, 417 & 503
*/
sub vcl_synth {
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";

    synthetic( {"
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html>
          <head>
            <title>Varnish cache server: "} + resp.status + " " + resp.reason + {" </title>
          </head>
          <body>
            <h1>Error "} + resp.status + " " + resp.reason + {"</h1>
            <p>"} + resp.reason + {"</p>
            <h3>Guru Meditation:</h3>
            <p>XID: "} + req.xid + {"</p>
            <hr>
            <p>Varnish cache server</p>
          </body>
        </html>
    "} );

    return (deliver);
}
