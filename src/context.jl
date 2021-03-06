# Low Level OpenCL context

type Context 
    id :: CL_context
    
    function Context(ctx_id::CL_context; retain=false)
        if retain
            @check api.clRetainContext(ctx_id)
        end
        ctx = new(ctx_id)
        finalizer(ctx, c -> release!(c))
        return ctx 
    end
end

function release!(ctx::Context)
    if ctx.id != C_NULL
        @check api.clReleaseContext(ctx.id)
        ctx.id = C_NULL 
    end
end

Base.pointer(ctx::Context) = ctx.id
@ocl_object_equality(Context)

function Base.show(io::IO, ctx::Context)
    dev_strs = [replace(d[:name], r"\s+", " ") for d in devices(ctx)]
    devs_str = join(dev_strs, ",")
    ptr_address = "0x$(hex(unsigned(Base.pointer(ctx)), WORD_SIZE>>2))"
    print(io, "<OpenCL.Context @$ptr_address on $devs_str>")
end

function ctx_notify_err(err_info::Ptr{Cchar}, priv_info::Ptr{Void},
                        cb::Csize_t, julia_func::Ptr{Void})
    err = bytestring(err_info)
    private = bytestring(convert(Ptr{Cchar}, err_info))
    callback = unsafe_pointer_to_objref(julia_func)::Function
    callback(err, private)::Ptr{Void}
end


const ctx_callback_ptr = cfunction(ctx_notify_err, Ptr{Void}, 
                                   (Ptr{Cchar}, Ptr{Void}, Csize_t, Ptr{Void}))

function raise_context_error(error_info, private_info)
    error("OpenCL.Context error: $error_info")
end


function Context(devs::Vector{Device};
                 properties=nothing,
                 callback::Union(Nothing, Function)=nothing)
    if isempty(devs)
        error("No devices specified for context")
    end
    if properties != nothing
        ctx_properties = _parse_properties(properties)
    else
        ctx_properties = C_NULL
    end
    if callback != nothing
        ctx_user_data = callback
    else
        ctx_user_data = raise_context_error 
    end
    n_devices = length(devs)
    device_ids = Array(CL_device_id, n_devices)
    for (i, d) in enumerate(devs)
        device_ids[i] = d.id 
    end
    err_code = Array(CL_int, 1)
    ctx_id = api.clCreateContext(ctx_properties, n_devices, device_ids,
                                 ctx_callback_ptr, ctx_user_data, err_code)
    if err_code[1] != CL_SUCCESS
        throw(CLError(err_code[1]))
    end 
    return Context(ctx_id, retain=true)
end


Context(d::Device; properties=nothing, callback=nothing) = 
        Context([d], properties=properties, callback=callback)

function Context(dev_type::CL_device_type;
                 properties=nothing, callback=nothing)
    if properties != nothing
        ctx_properties = _parse_properties(properties)
    else
        ctx_properties = C_NULL
    end
    if callback != nothing
        ctx_user_data = callback
    else
        ctx_user_data = raise_context_error
    end
    err_code = Array(CL_int, 1)
    ctx_id = api.clCreateContextFromType(ctx_properties, dev_type,
                                         ctx_callback_ptr, ctx_user_data, err_code)
    if err_code[1] != CL_SUCCESS
        throw(CLError(err_code[1]))
    end
    return Context(ctx_id, retain=true)
end

function Context(dev_type::Symbol;
                 properties=nothing, callback=nothing)
    Context(cl_device_type(dev_type),
            properties=properties, callback=callback)
end 


function properties(ctx_id::CL_context)
    size = Csize_t[0,]
    @check api.clGetContextInfo(ctx_id, CL_CONTEXT_PROPERTIES, 0, C_NULL, size)
    props = Array(CL_context_properties, size[1])
    @check api.clGetContextInfo(ctx_id, CL_CONTEXT_PROPERTIES,
                                size[1] * sizeof(CL_context_properties), props, C_NULL)
    
    #properties array of [key,value...]
    result = {}
    for i in 1:2:size[1]
        key = props[i]
        if key == CL_CONTEXT_PLATFORM
            value = Platform(cl_platform_id(props[i + 1]))
            push!(result, (key, value))
            continue
        #elseif key == CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE
        elseif key == CL_GL_CONTEXT_KHR
        elseif key == CL_EGL_DISPLAY_KHR
        elseif key == CL_GLX_DISPLAY_KHR
        elseif key == CL_WGL_HDC_KHR
        elseif key == CL_CGL_SHAREGROUP_KHR
            value = props[i + 1]
            push!(result, (key, value))
            continue
        elseif key == 0
            break
        else
            warn("Unknown OpenCL.Context property key encountered $key")
        end
    end
    return result
end

function properties(ctx::Context)
    properties(ctx.id)
end

#Note: properties list needs to be terminated with a NULL value!
function _parse_properties(props)
    if isempty(props)
        return C_NULL
    end 
    cl_props = Array(CL_context_properties, 0)
    for prop_tuple in props
        if length(prop_tuple) != 2
            error("Context property tuple must have length 2")
        end
        prop = prop_tuple[1]
        push!(cl_props, cl_context_properties(prop))
        if prop == CL_CONTEXT_PLATFORM
            val = prop_tuple[2]
            push!(cl_props, cl_context_properties(val.id))
        elseif prop == CL_WGL_HDC_KHR
            val = prop_tuple[2]
            push!(cl_props, cl_context_properties(val))
        elseif (prop == CL_GL_CONTEXT_KHR ||
                prop == CL_EGL_DISPLAY_KHR ||
                prop == CL_GLX_DISPLAY_KHR ||
                prop == CL_CGL_SHAREGROUP_KHR)
            #TODO: CHECK GL_PROPERTIES
            ptr = convert(Ptr{Void}, prop_tuple[2])
            push!(cl_props, cl_context_properties(ptr))
        else
            error("Invalid OpenCL Context property")
        end
    end
    push!(cl_props, cl_context_properties(C_NULL))
    return cl_props
end

function num_devices(ctx::Context)
    ndevices = Array(CL_uint, 1)
    @check api.clGetContextInfo(ctx.id, CL_CONTEXT_NUM_DEVICES,
                                sizeof(CL_uint), ndevices, C_NULL)
    return ndevices[1]
end

function devices(ctx::Context)
    n = num_devices(ctx)
    if n == 0
        return [] 
    end
    dev_ids = Array(CL_device_id, n)
    @check api.clGetContextInfo(ctx.id, CL_CONTEXT_DEVICES,
                                n * sizeof(CL_device_id), dev_ids, C_NULL)
    return [Device(id) for id in dev_ids]
end

function create_some_context()
    if isempty(platforms())
        error("No OpenCL.Platform available")
    end
    gpu_devices = devices(:gpu)
    if !isempty(gpu_devices)
        for dev in gpu_devices
            local ctx::Context
            try
                ctx = Context(dev)
            catch
                continue 
            end
            return ctx
        end
    end
    cpu_devices = devices(:cpu)
    if !isempty(cpu_devices)
        for dev in cpu_devices
            local ctx::Context
            try
                ctx = Context(dev)
            catch
                continue 
            end
            return ctx
        end
    end
    if isempty(gpu_devices) && isempty(cpu_devices)
        error("Unable to create any OpenCL.Context, no available devices")
    else
        error("Unable to create any OpenCL.Context, no devices worked")
    end
end
