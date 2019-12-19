@testset "models/vae.jl" begin

    Random.seed!(0)

    @testset "Vanilla VAE" begin
        T = Float32
        xlen = 4
        zlen = 2
        batch = 20
        test_data = hcat(ones(T,xlen,Int(batch/2)), -ones(T,xlen,Int(batch/2))) |> gpu
    
        enc = GenerativeModels.stack_layers([xlen, 64, 64, zlen*2], relu, Dense)
        enc_dist = CMeanVarGaussian{DiagVar}(enc)
    
        dec = GenerativeModels.stack_layers([zlen, 64, 64, xlen+1], relu, Dense)
        dec_dist = CMeanVarGaussian{ScalarVar}(dec)
    
        model = VAE(zlen, enc_dist, dec_dist) |> gpu
    
        loss = elbo(model, test_data)
        ps = params(model)
        @test length(ps) > 0
        @test isa(loss, Real)
    
        zs = rand(model.encoder, test_data)
        @test size(zs) == (zlen, batch)
        xs = rand(model.decoder, zs)
        @test size(xs) == (xlen, batch)     
    
        # test training
        params_init = get_params(model)
        opt = ADAM(5e-4)
        data = [(test_data,) for i in 1:10000]
        lossf(x) = elbo(model, x, β=1e-3)
        Flux.train!(lossf, params(model), data, opt)
    
        @test all(param_change(params_init, model)) # did the params change?
        zs = rand(model.encoder, test_data)
        xs = mean(model.decoder, zs)
        @debug maximum(test_data - xs)
        @test all(abs.(test_data - xs) .< 0.5) # is the reconstruction ok?
    end

    @testset "Wasserstein VAE" begin

        T = Float32
        xlen = 4
        zlen = 2
        batch = 20
        test_data = hcat(ones(T,xlen,Int(batch/2)), -ones(T,xlen,Int(batch/2))) # |> gpu

        enc = GenerativeModels.stack_layers([xlen, 10, 10, zlen], relu, Dense)
        enc_dist = CMeanGaussian{DiagVar}(enc, NoGradArray(ones(T,zlen)))

        dec = GenerativeModels.stack_layers([zlen, 10, 10, xlen], relu, Dense)
        dec_dist = CMeanGaussian{DiagVar}(dec, NoGradArray(ones(T,xlen)))

        model = VAE(zlen, enc_dist, dec_dist) # |> gpu

        # test training
        params_init = get_params(model)
        opt = ADAM()
        k = IMQKernel(1.0f0)
        mmd(x) = GenerativeModels.mmd_mean(model, x, k)
        data = (test_data,)
        lossf(x) = Flux.mse(x, mean(model.decoder, mean(model.encoder,x))) + mmd(x)
        GenerativeModels.update_params!(model, data, lossf, opt)
        ps = params(model)
        @test all(param_change(params_init, model)) 

        # this works well but has quite a large variance
        data = [(test_data,) for _ in 1:10000]
        Flux.train!(lossf, params(model), data, opt)
        zs = mean(model.encoder, test_data)
        xs = mean(model.decoder, zs)
        @debug maximum(abs.(test_data - xs))
        @test all(abs.(test_data - xs) .< 0.2) 

        msg = @capture_out show(model)
        @test occursin("VAE", msg)
        Random.seed!()  # reset the seed
    end

end
