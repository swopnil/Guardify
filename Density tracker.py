import cv2
import numpy as np
import time

class RealtimeMapVisualizer:
    def __init__(self, video_path, map_image_path):
        self.video = cv2.VideoCapture(video_path)
        self.map_image = cv2.imread(map_image_path)
        self.background_subtractor = cv2.createBackgroundSubtractorMOG2(history=200, varThreshold=16, detectShadows=False)
        self.people = []  # List to store person positions over time
        self.person_history = {}  # Dictionary to store person detection history
        self.next_id = 0  # For assigning unique IDs to detected people

    def process_frame(self):
        ret, frame = self.video.read()
        if not ret:
            return False

        # Apply background subtraction
        fg_mask = self.background_subtractor.apply(frame)
        _, binary = cv2.threshold(fg_mask, 244, 255, cv2.THRESH_BINARY)
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        # Filter contours by size
        min_contour_area = 100
        detected_people = [c for c in contours if cv2.contourArea(c) > min_contour_area]
        
        # Update people positions
        self.update_people(detected_people, frame.shape)
        
        return True

    def update_people(self, detected_people, frame_shape):
        frame_height, frame_width = frame_shape[:2]
        map_height, map_width = self.map_image.shape[:2]
        
        new_positions = []
        for person in detected_people:
            M = cv2.moments(person)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
                # Map frame coordinates to map image coordinates
                map_x = int((cx / frame_width) * map_width)
                map_y = int((cy / frame_height) * map_height)
                new_positions.append((map_x, map_y))
        
        # Update person history and filter persistent detections
        current_people = []
        for pos in new_positions:
            matched = False
            for person_id, history in self.person_history.items():
                if self.is_same_person(pos, history[-1]):
                    history.append(pos)
                    if len(history) > 10:  # Keep last 10 positions
                        history.pop(0)
                    matched = True
                    current_people.append((person_id, pos))
                    break
            if not matched:
                new_id = self.next_id
                self.next_id += 1
                self.person_history[new_id] = [pos]
                current_people.append((new_id, pos))
        
        # Remove people who haven't been detected recently
        for person_id in list(self.person_history.keys()):
            if len(self.person_history[person_id]) < 1:  # Remove if not detected in last 3 frames
                del self.person_history[person_id]
        
        # Update people list with current detections
        self.people = [pos for _, pos in current_people]

    def is_same_person(self, pos1, pos2, threshold=20):
        return np.sqrt((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2) < threshold

    def visualize(self):
        vis_image = self.map_image.copy()
        for person in self.people:
            cv2.circle(vis_image, person, 5, (0, 0, 255), -1)
        
        cv2.imshow('Map Visualization', vis_image)
        return cv2.waitKey(1) & 0xFF

    def run(self):
        while True:
            if not self.process_frame():
                break
            
            key = self.visualize()
            if key == ord('q'):
                break
            
            time.sleep(0.03)  # Adjust for desired frame rate

        self.video.release()
        cv2.destroyAllWindows()

# Usage
visualizer = RealtimeMapVisualizer('IMG_2180.MOV', 'IMG_2181.jpg')
visualizer.run()
