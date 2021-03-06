#include <iostream>

#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>
#include <cuda_device_runtime_api.h>
#include <device_launch_parameters.h>

#define BLUE_INDEX 0
#define RED_INDEX 1
#define GREEN_INDEX 2

void cudaCheckThrow(const char * file, unsigned line, const char *statement, cudaError_t error)
{
    std::string m_error_message;

    if(error == cudaSuccess)
    {
        return;
    }

    throw std::invalid_argument(cudaGetErrorString(error));
}

#define CHECK_ERROR(value) cudaCheckThrow(__FILE__, __LINE__, #value, value)

using namespace cv;

struct BRG_IMAGE
{
    uchar * b;
    uchar * r;
    uchar * g;
};

class BRG
{
public:
    uchar b;
    uchar r;
    uchar g;
    
    BRG operator-(const BRG & val)
    {
        BRG output;

        output.r = std::abs((int)r - (int)val.r);
        output.g = std::abs((int)g - (int)val.g);
        output.b = std::abs((int)b - (int)val.b);

        return output;
    }
    float operator^(int exponent)
    {
//        std::cout << "^: " << (float) b << ", " << (float) r << ", " << (float) g << " = " << std::pow((float)b, exponent) + std::pow((float)r,exponent) + std::pow((float)g, exponent) << std::endl;
       return std::pow((float)b, exponent) + std::pow((float)r,exponent) + std::pow((float)g, exponent); 
    }
};

::std::ostream & operator<<(::std::ostream & os, const BRG & c)
{
    os << "[" << (int) c.b << " " << (int) c.r << " " << (int) c.g << "]";
    return os;
}

__global__ void distanceCalc(BRG_IMAGE d_image, BRG * d_kMeans, uint cols, uint rows, float * output)
{
    uint colId = threadIdx.y;
    uint rowId = threadIdx.x;

    uint K = blockIdx.z;

    if(colId < cols && rowId < rows)
    {
        BRG pixel;
        uint pixelId = rowId * cols + colId;
        pixel.g = d_image.g[pixelId];
        pixel.r = d_image.r[pixelId];
        pixel.b = d_image.b[pixelId];

        output[K * cols * rows + pixelId] = pow(((float) pixel.b - (float) d_kMeans[K].b),2) + pow(((float) pixel.b - (float) d_kMeans[K].b),2) + pow(((float) pixel.b - (float) d_kMeans[K].b),2);
    }
}

__global__ void assigner(float * d_distanceBuffer, BRG_IMAGE d_image, BRG * d_kMeans, uint K, uint cols, uint rows, BRG_IMAGE d_output)
{
    uint colId = threadIdx.y;
    uint rowId = threadIdx.x;
   
    if(colId < cols && rowId < rows)
    {
        uint pixelId = rowId * cols + colId;
        uint minId = 0;
        float min = d_distanceBuffer[pixelId];

        for(int i = 1; i < K; i++)
        {
            float distanceVal = d_distanceBuffer[i * cols * rows + pixelId];
            if(distanceVal < min) 
            {
                min = distanceVal;
                minId = i; 
            }
        } 

        d_output.b[pixelId] = d_kMeans[minId].b; 
        d_output.r[pixelId] = d_kMeans[minId].r; 
        d_output.g[pixelId] = d_kMeans[minId].g; 
    }
}

bool gpuAlgo(const BRG_IMAGE & d_image, BRG * & d_kMeans, uint K, uint cols, uint rows, BRG_IMAGE & d_output)
{
    float * d_distanceBuffer;

    int length = cols * rows;
    
    CHECK_ERROR(cudaMalloc(&d_distanceBuffer, sizeof(float) * cols * rows * K));

    int blockXSize = 32;
    int blockYSize = 32;

    int gridXSize = (rows%blockXSize == 0) ? rows/blockXSize : rows / blockXSize + 1;
    int gridYSize = (cols%blockYSize == 0) ? cols/blockYSize : cols / blockYSize + 1;
    int gridZsize = K;

    dim3 blockSize(blockXSize, blockYSize, 1);
    dim3 gridSize(gridXSize, gridYSize, gridZsize);

    distanceCalc<<<gridSize, blockSize>>>(d_image, d_kMeans, cols, rows, d_distanceBuffer);

    CHECK_ERROR(cudaGetLastError());

    dim3 blockSize2(blockXSize, blockYSize, 1);
    dim3 gridSize2(gridXSize, gridYSize, 1);

    assigner<<<gridSize2, blockSize2>>>(d_distanceBuffer, d_image, d_kMeans, K, cols, rows, d_output); 
    CHECK_ERROR(cudaGetLastError());

}

void gpuMeans(const BRG_IMAGE & image, uint cols, uint rows, uint * initialFeaturePos, uint K, BRG_IMAGE & output)
{
    BRG_IMAGE d_image;
    BRG_IMAGE d_output;

    BRG * d_kMeans;
    BRG * h_kMeans = new BRG[K];
    
    int length = cols * rows;

    CHECK_ERROR(cudaMalloc(&d_image.g, sizeof(uchar) * length));    
    CHECK_ERROR(cudaMalloc(&d_image.r, sizeof(uchar) * length));    
    CHECK_ERROR(cudaMalloc(&d_image.b, sizeof(uchar) * length));    

    CHECK_ERROR(cudaMalloc(&d_output.g, sizeof(uchar) * length));    
    CHECK_ERROR(cudaMalloc(&d_output.r, sizeof(uchar) * length));    
    CHECK_ERROR(cudaMalloc(&d_output.b, sizeof(uchar) * length));    

    CHECK_ERROR(cudaMalloc(&d_kMeans, sizeof(BRG) * K));    

    CHECK_ERROR(cudaMemcpy(d_image.g, image.g, sizeof(uchar) * length, cudaMemcpyHostToDevice));
    CHECK_ERROR(cudaMemcpy(d_image.r, image.r, sizeof(uchar) * length, cudaMemcpyHostToDevice));
    CHECK_ERROR(cudaMemcpy(d_image.b, image.b, sizeof(uchar) * length, cudaMemcpyHostToDevice));

    for(int i = 0; i < K ; i++)
    {
        uint initCol = initialFeaturePos[2 * i];
        uint initRow = initialFeaturePos[2 * i + 1];

        h_kMeans[i].b = image.b[initCol + initRow * cols];
        h_kMeans[i].r = image.r[initCol + initRow * cols];
        h_kMeans[i].g = image.g[initCol + initRow * cols];
    }

    CHECK_ERROR(cudaMemcpy(d_kMeans, h_kMeans, sizeof(BRG) * K, cudaMemcpyHostToDevice));

    gpuAlgo(d_image, d_kMeans, K, cols, rows, d_output);

    CHECK_ERROR(cudaMemcpy(output.r, d_output.r, sizeof(uchar) * length, cudaMemcpyDeviceToHost));
    CHECK_ERROR(cudaMemcpy(output.g, d_output.g, sizeof(uchar) * length, cudaMemcpyDeviceToHost));
    CHECK_ERROR(cudaMemcpy(output.b, d_output.b, sizeof(uchar) * length, cudaMemcpyDeviceToHost));

}

void cpuKMeans(const BRG_IMAGE & image, uint cols, uint rows, uint * initialFeaturePos, uint K, BRG_IMAGE & output)
{
    BRG * kMeans = new BRG[K];
    
    memset(kMeans, 0, sizeof(BRG) * K);

    int * tempR = new int[K];
    int * tempG = new int[K];
    int * tempB = new int[K];

    int * occur = new int[K];

    for(int i = 0; i < K ; i++)
    {
        uint initCol = initialFeaturePos[2 * i];
        uint initRow = initialFeaturePos[2 * i + 1];

        tempB[i] = image.b[initCol + initRow * cols];
        tempR[i] = image.r[initCol + initRow * cols];
        tempG[i] = image.g[initCol + initRow * cols];
    }


    for(int i = 0; i < K; i++) 
        occur[i] = 1;
    
 //   std::cout << "Image" << std::endl;
    int iterations = 1;

    while(true && iterations < 10)
    {
        bool isSteadyState = true;

        for(int i = 0; i < K ; i++)
        {
            if(kMeans[i].g != tempG[i]/occur[i] || kMeans[i].r != tempR[i]/occur[i] || kMeans[i].b != tempB[i]/occur[i])
            {
                kMeans[i].g = tempG[i]/occur[i];
                kMeans[i].r = tempR[i]/occur[i];
                kMeans[i].b = tempB[i]/occur[i];

                isSteadyState &= false;
            }
            else
            {
                isSteadyState &= true;  
            }
        }

        if(isSteadyState)
            break;

        for(int c = 0; c < K; c++)
        {
            tempR[c]= 0;
            tempG[c]= 0;
            tempB[c]= 0;

            occur[c]= 0;
        }
       
        std::cout << "KMeans : " << std::endl;
        for(int i = 0; i< K ; i++)
        {
            std::cout << kMeans[i] << std::endl;
        } 

        int length = cols * rows;

        for(int pixelId = 0; pixelId < length; pixelId++)
        {
            BRG pixel;

            pixel.r = image.r[pixelId];
            pixel.b = image.b[pixelId];
            pixel.g = image.g[pixelId];

            std::vector<float> distances;

            for(int k = 0; k < K; k++)
            {
                BRG kVal = kMeans[k];
                distances.push_back((pixel - kVal)^2);                
            }

            int maxK = std::distance(distances.begin(), std::min_element(distances.begin(), distances.end()));

            if(maxK == 5)
            {
                std::cout << pixelId << ", " << pixel << ", ";
                for(const auto & it : distances)
                    std::cout << it << ", ";
                std::cout << std::endl;
            }

            tempR[maxK] += pixel.r;
            tempG[maxK] += pixel.g;
            tempB[maxK] += pixel.b;

            occur[maxK]++;

            output.b[pixelId] = kMeans[maxK].b; 
            output.r[pixelId] = kMeans[maxK].r; 
            output.g[pixelId] = kMeans[maxK].g; 

        }
        iterations++;
    }

        /*if(pixelId == 0)
        {
            std::cout << kMeans[maxK] << ", (";
            for(int r =0; r < K;r++) 
            {
                std::cout << kMeans[r] << " - " << ((pixel - kMeans[r])^2) << ", ";
            }
            std::cout << " )" << std::endl;
        }
            */
}

bool processImage(const BRG_IMAGE & image, uint cols, uint rows, BRG_IMAGE & outputImage)
{
    //uint initialFeaturePos[] = {647, 793, 1661,1019, 362,939};
    uint initialFeaturePos[] = {647, 793, 1661,1019, 362,939};
    //uint initialFeaturePos[] = {2 ,1, 0, 1};
    uint K = 3;

    if((sizeof(initialFeaturePos)/sizeof(uint))/(K*2) != 1 || (sizeof(initialFeaturePos)/sizeof(uint))%(K*2) != 0)
    {
        std::cerr << "Mismatch in K and intial features, K : " << K << ", initial feature count : " << ((float)sizeof(initialFeaturePos))/sizeof(uint)/(K*2)  << std::endl;
        return false;
    }

    for(int i = 0; i< K ; i++)
    {
        if(initialFeaturePos[i * 2] >= cols || initialFeaturePos[i * 2 + 1] >= rows)
        {
            std::cerr << "initial Positions out of bound, initial positions : (" 
                << initialFeaturePos[i * 2] << ", " << initialFeaturePos[i * 2 + 1] << ") , size : (" << cols << ", " << rows << ")" << std::endl;
            return false;
        }
    }

    uint length = cols * rows;
    
    BRG_IMAGE cpuOut;

    cpuOut.g = new uchar[length];
    cpuOut.b = new uchar[length];
    cpuOut.r = new uchar[length];

    memset(cpuOut.g, 255, length * sizeof(uchar));
    memset(cpuOut.r, 255, length * sizeof(uchar));
    memset(cpuOut.b, 255, length * sizeof(uchar));

    //cpuKMeans(image, cols, rows, initialFeaturePos, K, cpuOut);
    gpuMeans(image, cols, rows, initialFeaturePos, K, cpuOut);

    outputImage = cpuOut;

    return true;
        
} 

int main()
{
    try
    {
        Mat src = imread("/x01/bhashithaa/image/src/circles.jpg", IMREAD_COLOR);
        Mat matbrg[3];

        if(src.empty())
        {
            std::cerr << "Cannot load image" << std::endl;
            return 1;
        }
        else
        {
            std::cout << "Image loaded with Cols : " << src.cols << ", " << src.rows << std::endl;
        }

        split(src, matbrg);

        BRG_IMAGE brg;

        brg.b = matbrg[BLUE_INDEX].data;
        brg.r = matbrg[RED_INDEX].data;
        brg.g = matbrg[GREEN_INDEX].data;

       
        uint cols = src.cols;
        uint rows = src.rows;

        BRG_IMAGE outputImage;

        if(!processImage(brg, cols, rows, outputImage)) 
            return -1;

        //std::cout << (int)outputImage.b[0] << ", " << (int)outputImage.r[0] << ", " << (int) *outputImage.g << std::endl;
        Mat outputIM[3];
        outputIM[0] = Mat(rows, cols, CV_8UC1, outputImage.b);
        outputIM[1] = Mat(rows, cols, CV_8UC1, outputImage.r);
        outputIM[2] = Mat(rows, cols, CV_8UC1, outputImage.g);

        Mat outputComb;

        merge(outputIM,3, outputComb);    
        cv::imwrite("OutputKoala.jpg", outputComb);
    }
    catch(std::exception &ex)
    {
        std::cerr << "Exception thrown : " << ex.what() << std::endl;
    }
}
