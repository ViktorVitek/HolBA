signature scamv_configLib =
sig
    type scamv_config
    datatype gen_type = gen_rand
                      | prefetch_strides
                      | qc
                      | slice
                      | from_file
                      | from_list

    datatype obs_model = mem_address_pc
                       | cache_tag_index
                       | cache_tag_only
                       | cache_index_only
                       | cache_tag_index_part
                       | cache_tag_index_part_page
                       | cache_speculation
                       | cache_speculation_first
                       | time_div
                       | time_div_mem_pc
                       | time_div_speculation

    datatype hw_obs_model = hw_cache_tag_index
                          | hw_cache_index_numvalid
                          | hw_cache_tag_index_part
                          | hw_cache_tag_index_part_page
			  | hw_time


    val default_cfg : scamv_config
    val print_scamv_opt_usage : unit -> unit
    val scamv_getopt_config : unit -> scamv_config
end
