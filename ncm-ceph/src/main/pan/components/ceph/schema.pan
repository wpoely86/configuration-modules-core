# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

declaration template components/${project.artifactId}/schema;
 
include { 'quattor/schema' };

@documentation{ 
    desc = check that the ceph osd names are no ceph reserved paths 
    arg = ceph_component type
}
function valid_osd_names = {
    names = list();
    clusters = ARGV[0]['clusters'];
    foreach (name;cluster;clusters) {
        append(names, name);
    };

    foreach (name;cluster;clusters) {
        foreach (host;hvals;clusters[name]['osdhosts']) {
            foreach (osd;osdvals;clusters[name]['osdhosts'][host]['osds']) {
                foreach (idex;clname;names) {
                    if (match(osd,clname + '-\d+$')){
                        error("Osd path: " + osd + " is a ceph-reserved path!"); 
                        return(false);
                    };
                };
            };
        };
    };
   return(true);
};

@documentation{ 
    desc = checks the ceph crushmap, this includes uniqueness of bucket and rule name, recursive bucket typing, and rules using existing buckets
    arg = crushmap allowed bucket types
    arg = crushmap buckets definitions
    arg = rules to traverse crushmap
}
function is_crushmap = {
    names = list();
    types = ARGV[0];
    buckets = ARGV[1];
    rules = ARGV[2];
    #check types
    if(index('osd', types) == -1 || index('host', types) == -1) {
        error("Types should at least contain type 'osd' and 'host'.");
        return(false);
    };
    # check buckets (names, attrs, types)
    foreach(idx;bucket;buckets) {
        if (!is_bucket(bucket, names, types, 1)){
            return(false);
        };
    };
    # check rule names
    rulenames = list();
    foreach(idx;rule;rules) {
        if(index(rule['name'], rulenames) != -1) {
            error("Duplicate rule name " + rule['name']);
            return(false);
        } else {
            append(rulenames, rule['name']);
        };
        foreach(idx;step;rule['steps']) {
            if(index(step['take'], names) == -1) {
                error("rule " + rule['name'] + " selects a non-existing bucket " + step['take']);
                return(false);
            };
        };
    };
    true;
};

@documentation{ 
    desc = check the bucket type recursively, this includes attribute type and value checking and the uniqueness of names
    arg = bucket to check
    arg = list of already parsed bucket names
    arg = accepted bucket types
    arg = 1 if bucket is top bucket, 0 otherwise
}
function is_bucket = {
    bucket = ARGV[0];
    names = ARGV[1];
    types = ARGV[2];
    top = ARGV[3];
    if(!is_nlist(bucket)) {
        error("Invalid bucket! Bucket should be an nlist.");
        return(false);
    };    
    if(!exists(bucket['name']) || !is_string(bucket['name']) ) {
        error("Invalid bucket! Expected 'name' of type string");
        return(false);
    };
    if(!exists(bucket['type']) || !is_string(bucket['type']) ) {
        error("Invalid bucket! Expected 'type' of type string");
        return(false);
    } else {
        if(index(bucket['type'], types) == -1) {
            error("Invalid bucket type: " + bucket['type'] + " not in crushmap 'types'!");
            return(false);
        };
    };
    if(exists(bucket['alg']) && !is_ceph_crushmap_bucket_alg(bucket['alg'])) {
        error("Bucket attribute 'alg' invalid. Got " + bucket['alg']);
        return(false);
    };
    if(exists(bucket['hash']) && !is_long(bucket['hash'])) {
        error("Bucket attribute 'hash' invalid. Expected long, but got " + bucket['hash']);
        return(false);
    };
    if(exists(bucket['weight']) && (!is_double(bucket['weight']) || bucket['weight'] < 0)) {
        error("Bucket attribute 'weight' invalid. Expected positive double.");
        return(false);
    };
    if(exists(bucket['labels']) && !is_list(bucket['labels'])) {
        error("Invalid labels! Labels should be a list.");
        return(false);
    };     
    valids = list('name', 'type', 'alg', 'hash', 'weight', 'buckets', 'labels');
    if(top == 1){
        append(valids, 'defaultalg');
        append(valids, 'defaulthash');
    };
    foreach(attr;val;bucket) {
        if(index(attr, valids) == -1) {
            error("Attribute " + attr + " of bucket not supported!");
            retrun(false);
        };
    };        
    cnames = list();
    if(exists(bucket['labels'])) { 
        foreach(li;label;bucket['labels']) {
            append(cnames, format('%s-%s', bucket['name'], label));
        };
    } else {
        append(cnames, bucket['name']);   
    };
    foreach(ni;cname;cnames) {
        if(index(cname, names) != -1) {
            error("Duplicate bucket name " + cname);
            return(false);
        } else {
            append(names, cname);
        };
        debug("Bucket " + cname);
    };
    # Check attributes

    #recurse if buckets exists
    if(exists(bucket['buckets'])){
        foreach(idx;cbucket;bucket['buckets']) {
            if (!is_bucket(cbucket, names, types, 0)){
                return(false);
            };
        };
    };
    true;
};

@documentation{ ceph daemon config parameters }
type ceph_daemon_config = { 
    'osd_journal_size'  ? long(0..) 
    'osd_objectstore'   ? string
};

@documentation{ type for a generic ceph daemon }
type ceph_daemon = {
    'up'    : boolean = true
    'config'? ceph_daemon_config
};

@documentation{ ceph monitor-specific type }
type ceph_monitor = {
    include ceph_daemon
    'fqdn'  : type_fqdn
};

@documentation{ 
ceph osd-specific type 
The key of the ceph_osd should be the path to the mounted disk. 
This can be an absolute path or a relative one to /var/lib/ceph/osd/
journal_path should be the path to a journal file
This can be an absolute path or a relative one to /var/lib/ceph/log/
With labels osds can be grouped. This should also be defined in root. 
}
type ceph_osd = {
    include ceph_daemon
    'in'            ? boolean = true
    'journal_path'  ? string
    'crush_weight'  : double(0..) = 1.0
    'labels'        ? string[1..]
};

@documentation{ ceph osdhost-specific type }
type ceph_osd_host = {
    'fqdn'          : type_fqdn
    'osds'          : ceph_osd {}
};

@documentation{ ceph mds-specific type }
type ceph_mds = {
     include ceph_daemon
    'fqdn'  : type_fqdn
};

@documentation{ ceph cluster-wide config parameters }
type ceph_cluster_config = {
    'fsid'                      : string # Should be generated with uuidgen
    'filestore_xattr_use_omap'  : boolean = true
    'osd_journal_size'          : long(0..) = 10240
    'mon_initial_members'       : string [1..]
    'public_network'            : type_network_name
    'cluster_network'           ? type_network_name
    'auth_service_required'     : string = 'cephx' with match(SELF, '^(cephx|none)$')
    'auth_client_required'      : string = 'cephx' with match(SELF, '^(cephx|none)$')
    'auth_cluster_required'     : string = 'cephx' with match(SELF, '^(cephx|none)$')
    'osd_pool_default_pg_num'   : long(0..) = 600
    'osd_pool_default_pgp_num'  : long(0..) = 600
    'osd_pool_default_size'     : long(0..) = 3
    'osd_pool_default_min_size' : long(0..) = 2
    # the component sets this to false when generating crushmap itself, and true when crushmap is generated by ceph
    'osd_crush_update_on_start' ? boolean 
    'mon_cluster_log_to_syslog' : boolean = true
    'osd_objectstore'           ? string
};

@documentation{ ceph rados gateway type 
http://ceph.com/docs/master/radosgw/ 
}
type ceph_radosgw = {
    'config' ? nlist
};

@documentation{ ceph rados gateway host }
type ceph_radosgwh = {
    'fqdn'      : type_fqdn
    'gateways'  : ceph_radosgw{}
};

@documentation{ 
    desc = check it is a valid algorithm, also used in is_crushmap
    arg = bucket algoritm
}
function is_ceph_crushmap_bucket_alg = {
    if (!match(ARGV[0], '^(uniform|list|tree|straw2?)$')){
        error(ARGV[0] +  'is not a valid bucket algorithm');
        return(false);
    };
    true;
};
    
@documentation{ ceph crushmap bucket definition }
type ceph_crushmap_bucket = {
    'name'          : string #Must be unique
    'type'          : string # Must be in ceph_crushmap types
    'alg'           ? string with is_ceph_crushmap_bucket_alg(SELF)
    'hash'          ? long = 0 # 0 is rjenkins1
    'weight'        ? double(0..)
    'defaultalg'    : string = 'straw' with is_ceph_crushmap_bucket_alg(SELF)
    'defaulthash'   : long = 0
    'labels'        ? string[1..] # divide hierarchy on a osd label base
    'buckets'       ? nlist[] # the idea: recursive buckets
};

@documentation{ ceph crushmap rule step }
type ceph_crushmap_rule_choice = {
    'chtype'    : string with match(SELF, '^(choose firstn|chooseleaf firstn|choose indep)$')
    'number'    : long = 0
    'bktype'      : string 
};

@documentation{ ceph crushmap rule step }
type ceph_crushmap_rule_step = {
    'take'       : string # Should be a valid bucket
    'set_chooseleaf_tries' ? long
    'choices'    : ceph_crushmap_rule_choice[1..]
};

@documentation{ ceph crushmap rule definition }
type ceph_crushmap_rule = {
    'name'              : string #Must be unique
    'type'              : string = 'replicated' with match(SELF, '^(replicated|erasure)$')
    'ruleset'           ? long(0..) # ONLY set if you want to have multiple rules in the same or existing ruleset
    'min_size'          : long(0..) = 1
    'max_size'          : long(0..) = 10
    'steps'              : ceph_crushmap_rule_step[1..] 
};

@documentation{ 
ceph crushmap definition 
The crushmap defines some types of buckets,
a hierarchical bucket structure,
rules for traversing these buckets
and tunables for magic numbers.
}
type ceph_crushmap = {
    'types'     : string [1..]
    'buckets'   : ceph_crushmap_bucket [1..]
    'rules'     : ceph_crushmap_rule[1..]
    'tunables'  ? long{} 
} with is_crushmap(SELF['types'], SELF['buckets'], SELF['rules']); 

@documentation{ overarching ceph cluster type, with osds, mons and msds }
type ceph_cluster = {
    'config'                    : ceph_cluster_config
    'osdhosts'                  : ceph_osd_host {}
    'monitors'                  : ceph_monitor {1..}
    'mdss'                      ? ceph_mds {}
    'radosgwh'                  ? ceph_radosgwh {} # gateways are not being deployed yet, only the config
    'deployhosts'               : type_fqdn {1..} # key should match value of /system/network/hostname of one or more hosts of the cluster
    'crushmap'                  ? ceph_crushmap
};

@documentation{ ceph clusters }
type ${project.artifactId}_component = {
    include structure_component
    'clusters'         : ceph_cluster {}
    'ceph_version'     ? string with match(SELF, '[0-9]+\.[0-9]+(\.[0-9]+)?')
    'deploy_version'   ? string with match(SELF, '[0-9]+\.[0-9]+\.[0-9]+')
    'key_accept'       ? string with match(SELF, '^(first|always)$') # explicit accept host keys
    'ssh_multiplex'    : boolean = true
} with valid_osd_names(SELF);

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
