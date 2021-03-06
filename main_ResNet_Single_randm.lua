require 'torch'
require 'image'
require 'nn'
require 'cudnn'
require 'cunn'
require 'optim'
require 'gnuplot'
require 'cutorch'
require 'hzproc'

trainGT = torch.load('/home/zxw/Baidu/cache/trainGT.t7')              -- this table contains the name of the images 
trainPath = torch.load('/home/zxw/Baidu/cache/trainPath.t7')          -- the label of each image
testGT = torch.load('/home/zxw/Baidu/cache/testGT.t7')
testPath = torch.load('/home/zxw/Baidu/cache/testPath.t7')

weight = torch.load('/home/zxw/Baidu_XJTU_logo_classfication/cache/train_weight.t7')

MaxEpoch = 1920
batchsize = 4

    torch.setdefaulttensortype('torch.CudaTensor')

-- set paths
imgpath = paths.concat('/home/zxw/Baidu/datasets/paddedImage','%s')
model_path = '/home/zxw/Baidu_XJTU_logo_classfication/ResNet.lua'

model_opt = {} 
pretrain = '/home/zxw/fast-rcnn-torch/models/ResNet/resnext_101_64x4d-100c.t7'   -- pretrain file which download from https://github.com/facebookresearch/ResNeXt
model_save_path = '/home/zxw/Baidu/TrainedModel/ResNet5e-4_NoFlip_batch4/'	  -- the final fc layer nn.Linear(2048,1000) is replaced by nn.Linear(2048,100)


annotype = 'modelID'
batchnum_in_one_epoch=#trainPath/batchsize

if annotype == 'modelID'  then
       model_opt.classnumber = 100
else
       model_opt.classnumber = 7
end

local accuracy = {}
-- Annotation Fetcher


function getImage(i)
  return image.load(getImagePath(i),3,'float')
end

function getImagePath(i)
  return string.format(imgpath,i)
end

function trainN(MaxEpoch,batchsize)
       --net:train()
    local itershow = batchnum_in_one_epoch
    local TotalIter = MaxEpoch*batchnum_in_one_epoch

    local inputs = torch.Tensor(batchsize,3,224,224)
    local Targets = torch.Tensor(batchsize)
    local sum_loss = 0
    --local sum_model_loss = 0
    local Epoch = 0
    local rand_r = 1

    torch.setdefaulttensortype('torch.FloatTensor')
    local shuffle = torch.randperm(2180)
    torch.setdefaulttensortype('torch.CudaTensor')

    iter = 0
    index = 1
    while iter<TotalIter do
        -- preparing a batch for network																			
        for t = 1,batchsize do	

            local temp = getImage(trainPath[shuffle[index]])
            Targets[t] = tonumber(trainGT[trainPath[shuffle[index]]])    --change here for different attribu

	    temp = ImageColorAug(temp)
            temp = ImageSharpnessAug(temp)
            local r = (rand_r - 0.5)*math.pi/3
            temp = image.rotate(temp, r)   

            inputs[{{t},{},{},{}}] = image.scale(temp,224,224)           --rescale and load this picture
            index = index + 1

            if index == #trainPath then
                         index = 1
                         torch.setdefaulttensortype('torch.FloatTensor')
                         shuffle = torch.randperm(#trainPath)
    			 torch.setdefaulttensortype('torch.CudaTensor')
            end 
        end

        for i=1,3 do -- over each image channel
            mean=inputs[{ {}, {i}, {} ,{}  }]:mean() -- mean estimation
            inputs[{ {}, {i}, {}, {}  }]:add(-mean) -- mean subtraction
        end
        --Targets:add(1)


        local err
        feval = function(x)
            net:zeroGradParameters()
            local outputs = net:forward(inputs:cuda())
            err = criterion:forward(outputs:cuda(),Targets:cuda())
            local err_out = criterion:backward(outputs:cuda(),Targets:cuda()) 
	     net:backward(inputs,err_out)
	     --print(gradParameters:sum())
	     return err, gradParameters
	end

        optim.sgd(feval,parameters,sgd_params)

        iter = iter+1
        sum_loss = sum_loss+err
	rand_r = math.random()

        if iter%100==0 then
            print(string.format('Iteration = %d, Classification Loss = %2.4f',iter,sum_loss/100))
            sum_loss = 0
        end
        
	--test for every 16 epoch
        if iter%2000==0 then

            --Epoch = Epoch+4
                net:clearState() 
                torch.save(model_save_path..model_opt.classnumber..'Class_'..'ResNet' ..iter..'iteration' .. '.t7',net)
      	        collectgarbage()

 		-- validate
		net:evaluate()
		local Suc = 0
		--print(#testPath)
		for i = 1, #testPath do

		      --print(batchsize)   
		      local inputs = torch.CudaTensor(1,3,224,224)
		      local Predict = torch.CudaTensor(1)
		      local Targets = torch.CudaLongTensor(1)

		      for t = 1,1 do
				  local temp = getImage(testPath[i])
				  Targets[t] = testGT[testPath[i]]
				  inputs[{{t},{},{},{}}] =image.scale(temp,224,224)
		      end
		      for i=1,3 do -- over each image channel
				  mean=inputs[{ {}, {i}, {} ,{}  }]:mean() -- mean estimation
				  inputs[{ {}, {i}, {}, {}  }]:add(-mean) -- mean subtraction
		      end
		      outputs = net:forward(inputs:cuda())
		      _,Predict = torch.max(outputs,2)
		      Suc = Suc + ((Predict:view(-1)):eq(Targets):sum())
		end

                print(string.format('Classification = %d,  Classification Pricision  = %f',Suc, Suc/#testPath))  	
		table.insert(accuracy,(1-Suc/#testPath))

		if sgd_params.learningRate < 1e-5  then
          	    opt_conf.learningRateDecay = 0
        	end

	        if iter %5000== 0 then

		     gnuplot.pngfigure('/home/zxw/Baidu/TrainedModel/ResNet5e-4_NoFlip_batch4/'.. iter..'_test.png')
		     gnuplot.axis{'','',0,0.2}

                     torch.setdefaulttensortype('torch.FloatTensor')
		     gnuplot.plot('Accuracy',torch.Tensor(accuracy))
    		     torch.setdefaulttensortype('torch.CudaTensor')

		     gnuplot.close()


  		     local curves ={}
		     torch.save(paths.concat('/home/zxw/Baidu/TrainedModel/ResNet5e-4_NoFlip_batch4', iter..'Result.t7'), accuracy)

	        end
            	net:training()
        end

    end
end


function ImageColorAug(img)
    local randR = torch.rand(1)*0.06+0.97
    local randG = torch.rand(1)*0.06+0.97                                                
    local randB = torch.rand(1)*0.06+0.97
    img[1]:mul(randR:float()[1])
    img[2]:mul(randG:float()[1])                              
    img[3]:mul(randB:float()[1])
    return img
end

function ImageSharpnessAug(img)
    local blurK = torch.FloatTensor(5,5):fill(1/25)
    local Cur_im_blurred = image.convolve(img,blurK,'same')
    local cur_im_residue = torch.add(img,-1,Cur_im_blurred)
    local ranSh = torch.rand(1)*1.5
    img:add(ranSh:float()[1],cur_im_residue)
    return img
end

function ImageVFilp(img,label)
    local resimg = image.vflip(img)
    label[{{},{5}}] = - label[{{},{5}}]
    label[{{},{2}}] = 320 - label[{{},{2}}]

    return resimg,label
end

function ImageHFilp(img,label)
    local resimg = image.hflip(img)
    label[{{},{5}}] = - label[{{},{5}}]
    label[{{},{1}}] = 320 - label[{{},{1}}]

    return resimg,label
end


net = dofile(model_path)()   

parameters,gradParameters = net:getParameters()
criterion = nn.CrossEntropyCriterion(weight:cuda())

sgd_params = {  
       learningRate = 1e-2, 
       learningRateDecay = 5e-4,
       nesterov = true,  
       weightDecay = 1e-5,  
       dampening = 0.0,
       momentum = 1e-4  
}



--test() -- 
trainN(MaxEpoch,batchsize)


