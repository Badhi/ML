#include <iostream>

#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

#define BLUE_INDEX 0
#define RED_INDEX 1
#define GREEN_INDEX 2

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

        output.r = r - val.r;
        output.g = g - val.g;
        output.b = b - val.b;

        return output;
    }
    float operator^(int exponent)
    {
       return std::pow((float)b, 2) + std::pow((float)r,2) + std::pow((float)g,2); 
    }
};

::std::ostream & operator<<(::std::ostream & os, const BRG & c)
{
    os << "[" << (int) c.b << " " << (int) c.r << " " << (int) c.g << "]";
    return os;
}

void cpuKMeans(const BRG_IMAGE & image, uint cols, uint rows, uint * initialFeaturePos, uint K, BRG_IMAGE & output)
{
    BRG * kMeans = new BRG[K];
    
    std::cout << "Image" << std::endl;

    for(int i = 0; i < K ; i++)
    {
        uint initCol = initialFeaturePos[2 * i];
        uint initRow = initialFeaturePos[2 * i + 1];
        std::cout << initCol + initRow * cols << std::endl;
        kMeans[i].b = image.b[initCol + initRow * cols];
        kMeans[i].r = image.r[initCol + initRow * cols];
        kMeans[i].g = image.g[initCol + initRow * cols];
    }
    
    std::cout << "KMeans : " << std::endl;
    for(int i = 0; i < K; i++)
    {
        std::cout << kMeans[i] << std::endl;
    }

    int length = cols * rows;

    for(int pixelId = 0; pixelId < 1; pixelId++)
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
            std::cout << " k = " << k << std::endl;
            std::cout << (int) pixel.g << " - " << (int) kVal.g << std::endl;
            std::cout << (int) pixel.r << " - " << (int) kVal.r << std::endl;
            std::cout << (int) pixel.b << " - " << (int) kVal.b << std::endl;

            std::cout << ((pixel - kVal)^2) << std::endl;
        }
        
        int maxK = std::distance(distances.begin(), std::min_element(distances.begin(), distances.end()));
    

        output.b[pixelId] = kMeans[maxK].b; 
        output.r[pixelId] = kMeans[maxK].r; 
        output.g[pixelId] = kMeans[maxK].g; 
    }
}

void processImage(const BRG_IMAGE & image, uint cols, uint rows, BRG_IMAGE & outputImage)
{
//    uint initialFeaturePos[] = {647, 793, 1661,1019, 362,939};
    uint initialFeaturePos[] = {3 ,2, 1, 2};
    uint K = 2;

    if((sizeof(initialFeaturePos)/sizeof(uint))/(K*2) != 1 || (sizeof(initialFeaturePos)/sizeof(uint))%(K*2) != 0)
    {
        std::cerr << "Mismatch in K and intial features, K : " << K << ", initial feature count : " << ((float)sizeof(initialFeaturePos))/sizeof(uint)/(K*2)  << std::endl;
        return;
    }

    for(int i = 0; i< K ; i++)
    {
        if(initialFeaturePos[i * 2] > cols || initialFeaturePos[i * 2 + 1] > rows)
        {
            std::cerr << "initial Positions out of bound, initial positions : (" 
                << initialFeaturePos[i * 2] << ", " << initialFeaturePos[i * 2 + 1] << ") , size : (" << cols << ", " << rows << ")" << std::endl;
            return;
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

    cpuKMeans(image, cols, rows, initialFeaturePos, K, cpuOut);

    outputImage = cpuOut;
        
} 

int main()
{
    try
    {
        Mat src = imread("/x01/bhashithaa/image/src/temp.jpg", IMREAD_COLOR);
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

        std::cout << matbrg[0] << std::endl;
        std::cout << matbrg[1] << std::endl;
        std::cout << matbrg[2] << std::endl;
  
        BRG_IMAGE brg;

        brg.b = matbrg[BLUE_INDEX].data;
        brg.r = matbrg[RED_INDEX].data;
        brg.g = matbrg[GREEN_INDEX].data;

       
        uint cols = src.cols;
        uint rows = src.rows;

        BRG_IMAGE outputImage;

        processImage(brg, cols, rows, outputImage); 

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
