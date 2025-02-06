import cv2
import numpy as np
from ultralytics import YOLO
from process.computer_vision_models.main import PlateSegmentation
from process.ocr_extraction.ocr import OcrProcess


class PlateRecognition:
    def __init__(self):
        self.vehicle_detector = YOLO("yolov8n.pt")  # Use YOLOv8 pre-trained model
        self.plate_segmenter = PlateSegmentation()
        self.ocr_processor = OcrProcess()

    def process_frame(self, frame: np.ndarray):
        # Detect vehicles
        results = self.vehicle_detector(frame, stream=True)

        for result in results:
            for box in result.boxes:
                # Extract vehicle detection info
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                vehicle_bbox = [x1, y1, x2, y2]
                vehicle_type = self.vehicle_detector.names[int(box.cls[0])]

                # Crop vehicle image
                vehicle_crop = frame[y1:y2, x1:x2]

                # Detect plate
                has_plate, plate_info = self.plate_segmenter.check_vehicle_plate(vehicle_crop)

                if has_plate:
                    plate_mask, plate_bbox, _ = self.plate_segmenter.extract_plate_info(vehicle_crop, plate_info)

                    # Crop plate image
                    plate_crop = self.plate_segmenter.image_plate_crop(vehicle_crop, plate_bbox)

                    # Perform OCR to extract text
                    plate_text = self.ocr_processor.text_detection(plate_crop)

                    # Draw plate text on the frame
                    cv2.putText(
                        frame,
                        f"{vehicle_type}: {plate_text}",
                        (x1, y1 - 10),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.6,
                        (0, 255, 0),
                        2,
                    )

                # Draw vehicle bounding box on the frame
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(
                    frame,
                    vehicle_type,
                    (x1, y1 - 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (0, 255, 0),
                    2,
                )

        return frame


def main():
    video_path = r'C:\\Users\\belli\\Downloads\\Plates.mp4'
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        print("No se pudo abrir el video.")
        return

    plate_recognition = PlateRecognition()

    while True:
        ret, frame = cap.read()
        if not ret:
            print("Fin del video.")
            break

        # Process the frame
        processed_frame = plate_recognition.process_frame(frame)

        # Display the frame
        cv2.imshow("Vehicle and Plate Detection", processed_frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
