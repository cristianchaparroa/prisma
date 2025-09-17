import React, { useRef, useEffect } from 'react';
import * as THREE from 'three';

interface PrismaProps {
    color?: number;
    opacity?: number;
    size?: number;
    width?: number;
    height?: number;
}

const Prisma: React.FC<PrismaProps> = ({
                                           color = 0x4A90E2,
                                           opacity = 0.7,
                                           size = 0.6,
                                           width = 60,
                                           height = 60,
                                           verticalScale = 1.5
                                       }) => {
    const mountRef = useRef<HTMLDivElement>(null);
    const animationIdRef = useRef<number | null>(null);
    const rendererRef = useRef<THREE.WebGLRenderer | null>(null);

    useEffect(() => {
        if (!mountRef.current) return;

        // Scene setup
        const scene = new THREE.Scene();
        const camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
        const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });

        renderer.setSize(width, height);
        renderer.setClearColor(0x000000, 0);
        mountRef.current.appendChild(renderer.domElement);

        // Create material
        const material = new THREE.MeshLambertMaterial({
            color: color,
            transparent: true,
            opacity: opacity
        });

        // Create single bipyramid geometry
        const geometry = new THREE.OctahedronGeometry(size);
        const prisma = new THREE.Mesh(geometry, material);
        scene.add(prisma);

        // Lighting
        const ambientLight = new THREE.AmbientLight(0x404040, 1.0);
        const directionalLight = new THREE.DirectionalLight(0xffffff, 1.5);
        directionalLight.position.set(5, 5, 5);

        scene.add(ambientLight);
        scene.add(directionalLight);

        // Camera position
        camera.position.z = 3;
        camera.position.y = 0;
        camera.lookAt(0, 0, 0);

        // Store renderer ref
        rendererRef.current = renderer;

        // Animation loop
        const animate = () => {
            prisma.rotation.y += 0.01;
            renderer.render(scene, camera);
            animationIdRef.current = requestAnimationFrame(animate);
        };

        animate();

        // Cleanup
        return () => {
            if (animationIdRef.current) {
                cancelAnimationFrame(animationIdRef.current);
            }

            if (mountRef.current && renderer.domElement && mountRef.current.contains(renderer.domElement)) {
                mountRef.current.removeChild(renderer.domElement);
            }

            renderer.dispose();
            geometry.dispose();
            material.dispose();
        };
    }, [color, opacity, size, width, height]);

    return (
        <div
            ref={mountRef}
            style={{
                width: `${width}px`,
                height: `${height}px`,
                background: 'transparent',
                display: 'inline-block'
            }}
        />
    );
};


export default Prisma;
