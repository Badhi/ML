clear all;
close all;

inputImage = imread('circles.jpg');

%InitialPoints = [980,75; 475, 483;  950, 485];
%InitialPoints = [980,75; 475, 483; 950, 485;  743, 776];
%InitialPoints = [647, 793; 1661,1019; 362,939];
InitialPoints = fliplr([647, 793; 1661,1019; 362,939]) + 1;
%InitialPoints = fliplr([3 2; 1 2]);

KPointCount = size(InitialPoints,1);

[xSize, ySize, zSize] = size(inputImage);

if(sum(InitialPoints(:, 1) > xSize) ||  sum(InitialPoints(:, 2) > ySize))
  printf("Initial points out of bound");
  return
endif

for i = 1 : KPointCount
  initialValues(i,:) = inputImage(InitialPoints (i,1), InitialPoints (i,2),:);
endfor

while true

  %initialValues
  
  for i = 1 : KPointCount
    imageDistance(:,:,i) =  (double(inputImage(:,:,1)) - double(initialValues(i,1))).^2 + (double(inputImage(:,:,2)) - double(initialValues(i,2))).^2 + (double(inputImage(:,:,3)) - double(initialValues(i,3))).^2;
  endfor

  %imageDistance(1,1,:)
  
  minValues = min(imageDistance, [], 3);

  mask = (imageDistance == minValues );

    %printf("Previous");
    %initialValues
      
  for k = 1 : KPointCount
    for i = 1 : 3     
      tempInitialValues(k, i) = sum(sum(mask(:,:,k).* double(inputImage(:,:,i)) ))/sum(sum(mask(:,:,k)));
    endfor
  endfor
  
  if(tempInitialValues == initialValues)
    break;
  else    
    initialValues = tempInitialValues;
  endif
  %printf("After");
  %initialValues
endwhile

maskTot = zeros(xSize,ySize, 3, "uint8");

for k = 1 : KPointCount
  for i = 1:3
    maskTot(:,:,i) = maskTot(:,:,i) + mask(:,:,k) * initialValues(k,i);
  endfor
endfor

imshow(maskTot);