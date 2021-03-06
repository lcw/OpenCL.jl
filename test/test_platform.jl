using FactCheck

import OpenCL 
const cl = OpenCL

macro throws_pred(ex) FactCheck.throws_pred(ex) end 

facts("OpenCL.Platform") do 
    
    context("Platform Info") do
        @fact length(cl.platforms()) => cl.num_platforms()
        for p in cl.platforms()
            @fact p != nothing => true
            @fact pointer(p) != C_NULL => true
            for k in [:profile, :version, :name, :vendor, :extensions]
                @fact p[k] == cl.info(p, k) => true
            end
            @fact cl.opencl_version(p)[1] => 1
            @fact 0 <= cl.opencl_version(p)[2] <= 2  => true
         end
     end
     
     context("Platform Equality") do 
        platform       = cl.platforms()[1]
        platform_copy  = cl.platforms()[1]
        
        @fact pointer(platform) => pointer(platform_copy) 
        @fact hash(platform) => hash(platform_copy)
        @fact isequal(platform, platform) => true
        
        if length(cl.platforms()) > 1
            for p in cl.platforms()[2:end]
                @fact pointer(platform) == pointer(p) => false
                @fact hash(platform) == hash(p) => false
                @fact isequal(platform, p) => false
            end
        end
    end
end
